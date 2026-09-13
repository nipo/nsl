"""The transactor of a board, over the bus it is plugged into.

One batch of commands is one frame, and one frame is one transfer:
where it ends is where a short packet ends it, so nothing here has to
look for the edges of anything.  What carries it checks what it
carries and stops the far end when nobody is reading, which is what
this asks of a transport.
"""

from __future__ import annotations

import asyncio
from collections import deque

import ausb
import usb1
from ausb.exception import TransferTimeout
from ausb.handle import BulkInEndpoint, BulkOutEndpoint

VENDOR_ID = 0xdead
PRODUCT_ID = 0x5d10

VENDOR_CLASS = 0xff
BULK = 2

# Largest answer expected in one go.  A read of many blocks is bigger
# than this, and comes in as the several transfers it takes.
READ_SIZE = 65536

# Seconds to wait for an answer.  A batch is as long as what it asks
# of a card: a poll waiting for one to finish powering up, or one
# waiting for a block to be stored, holds the answer until it is done.
ANSWER_TIMEOUT = 30.0

# Transfers kept posted on the way in.  A device with nothing to put
# in them costs nothing; one with something to say finds somewhere to
# put it rather than waiting for this end to ask.
READ_DEPTH = 4

# Milliseconds a posted transfer waits before it is posted again.  A
# transfer waiting on a device with nothing to say is the normal state
# of this, so what this bounds is how long a dead device goes unnoticed
# rather than how long an answer may take.
POST_TIMEOUT = 60000

# Seconds a device takes to come back after a bus reset
RESET_SETTLE = 1.5


class NoDevice(Exception):
    pass


class FramedLink:
    """Frames to and from a device, as a channel a transactor can use."""

    def __init__(self, device, interface, ep_out, ep_in, mps):
        self.device = device
        self.interface = interface
        self.out = ep_out
        self.in_ = ep_in
        self.mps = mps

        # Answers still owed, in the order the batches asking for them
        # went out, and the task handing them over
        self.__owed: deque = deque()
        self.__reader: asyncio.Task | None = None
        self.__closing = False
        # What has arrived of the frame being put back together
        self.__frame = bytearray()
        # Batches go out one at a time so that what is owed is in the
        # order the wire carries it
        self.__lock = asyncio.Lock()

    @staticmethod
    def __endpoints(descriptor):
        """The vendor interface of a device and the bulk pair on it."""
        for index, interface in enumerate(descriptor[0]):
            setting = interface[0]
            if setting.classes[0] != VENDOR_CLASS:
                continue

            out_addr = in_addr = None
            mps = 0
            for ep in setting:
                if (ep.attributes & 0x3) != BULK:
                    continue
                if ep.address & 0x80:
                    in_addr = in_addr if in_addr is not None else ep.address
                else:
                    out_addr = out_addr if out_addr is not None else ep.address
                mps = max(mps, ep.max_packet_size)

            if out_addr is not None and in_addr is not None:
                return index, out_addr, in_addr, mps

        raise NoDevice("device has no vendor interface with a bulk pair")

    @staticmethod
    def __find(context, vendor_id, product_id):
        found = context.device_get(vendor_id=vendor_id, product_id=product_id)
        if found is None:
            raise NoDevice(f"no {vendor_id:04x}:{product_id:04x} on the bus")
        return found

    @classmethod
    async def open(cls, context, vendor_id=VENDOR_ID, product_id=PRODUCT_ID,
                   reset: bool = True):
        if reset:
            # A session that died leaves the device holding whatever it
            # was in the middle of, and no command can talk it out of
            # that.  A bus reset can: it takes the device back through
            # enumeration, and what is behind the endpoints is held in
            # reset until it comes out the other side.
            handle = cls.__find(context, vendor_id, product_id).open()
            try:
                handle.handle.resetDevice()
            except usb1.USBError:
                pass
            del handle
            await asyncio.sleep(RESET_SETTLE)

        device = cls.__find(context, vendor_id, product_id).open()
        index, out_addr, in_addr, mps = cls.__endpoints(device.descriptor)

        try:
            device.handle.detachKernelDriver(index)
        except (usb1.USBErrorNotFound, usb1.USBErrorNotSupported,
                usb1.USBErrorAccess):
            pass
        device.handle.claimInterface(index)

        ep_out = BulkOutEndpoint(device, out_addr, mps)
        ep_in = BulkInEndpoint(device, in_addr, mps)
        ep_out.resume()
        ep_in.resume()

        self = cls(device, index, ep_out, ep_in, mps)
        await self.drain()
        return self

    async def drain(self):
        """Whatever a session that died left the device holding."""
        from ausb.exception import TransferTimeout
        try:
            while True:
                self.in_.read_sync(self.mps, timeout=20)
        except TransferTimeout:
            pass

    async def __reader_loop(self):
        """Puts frames back together and hands them to whoever asked.

        Several transfers stay posted at once and a bulk endpoint
        completes them in the order they went in, so what comes out of
        them is the byte stream in order, and where a short packet
        falls is where a frame ends.
        """
        posted: deque = deque()
        try:
            while not self.__closing:
                while len(posted) < READ_DEPTH:
                    posted.append(asyncio.ensure_future(
                        self.in_.read(READ_SIZE, timeout=POST_TIMEOUT)))

                try:
                    chunk = await posted.popleft()
                except TransferTimeout:
                    # Nothing came, which is what waiting on an idle
                    # device looks like.  Ask again.
                    continue

                self.__frame += chunk

                if len(chunk) < READ_SIZE:
                    frame, self.__frame = bytes(self.__frame), bytearray()
                    if self.__owed:
                        waiter = self.__owed.popleft()
                        if not waiter.done():
                            waiter.set_result(frame)
        except asyncio.CancelledError:
            raise
        except BaseException as exc:  # noqa: BLE001 — forward it on
            while self.__owed:
                waiter = self.__owed.popleft()
                if not waiter.done():
                    waiter.set_exception(exc)
        finally:
            for task in posted:
                task.cancel()

    async def __write_frame(self, data: bytes):
        # A batch leaves as fast as the device takes it, and a device
        # in the middle of a write takes it as fast as a card stores
        # blocks, so this waits as long as an answer may.
        await self.out.write(bytes(data), timeout=POST_TIMEOUT)
        if len(data) % self.mps == 0:
            # A transfer whose length is a whole number of packets
            # needs an empty one behind it to say it has ended.
            await self.out.write(b"", timeout=POST_TIMEOUT)

    async def exchange(self, data: bytes) -> bytes:
        """One batch out, the answer to it back.

        Several of these can be in the air at once: what the device
        has not got to yet waits in it rather than in a host that
        would otherwise be holding the wire idle between batches.
        """
        if self.__reader is None:
            self.__reader = asyncio.ensure_future(self.__reader_loop())

        waiter = asyncio.get_running_loop().create_future()
        async with self.__lock:
            self.__owed.append(waiter)
            await self.__write_frame(data)

        return await asyncio.wait_for(waiter, ANSWER_TIMEOUT)

    async def close(self):
        self.__closing = True
        if self.__reader is not None:
            self.__reader.cancel()
            self.__reader = None
        self.device.handle.releaseInterface(self.interface)
