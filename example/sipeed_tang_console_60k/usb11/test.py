import asyncio
import ausb
import time
import asyncclick as click
import usb1
import logging
from acrobe.adapter.model import Adapter, AdapterInfo, adapter_db
from acrobe.cli import base
from ausb.handle import BulkOutEndpoint, BulkInEndpoint

@adapter_db.register(AdapterInfo("Test", vid=0xdead, pid=0xbeef))
class TestAdapter(Adapter):
    def __init__(self, name, info=None, descriptor=None):
        super().__init__(name, info, descriptor)

class Transport:
    def __init__(self, device, interface_index: int,
                 ep_out: BulkOutEndpoint, ep_in: BulkInEndpoint,
                 mps: int,
                 logger: logging.Logger):
        self.__device = device
        self.__interface = interface_index
        self.__ep_out = ep_out
        self.__ep_in = ep_in
        self.__mps = mps
        self.__lock = asyncio.Lock()
        self.__logger = logger
        self.__rx_leftovers = b''

    @staticmethod
    def __find_interface(device):
        config = device.descriptor[0]
        BULK = 2
        VENDOR_CLASS = 0xFF

        for i, interface in enumerate(config):
            setting = interface[0]
            if setting.classes[0] != VENDOR_CLASS:
                continue
            ep_out_addr = ep_in_addr = None
            ep_out_mps = ep_in_mps = 0
            for ep in setting:
                if (ep.attributes & 0x3) != BULK:
                    continue
                is_in = bool(ep.address & 0x80)
                if is_in and ep_in_addr is None:
                    ep_in_addr = ep.address
                    ep_in_mps = ep.max_packet_size
                elif not is_in and ep_out_addr is None:
                    ep_out_addr = ep.address
                    ep_out_mps = ep.max_packet_size
            if ep_out_addr is not None and ep_in_addr is not None:
                return i, ep_out_addr, ep_in_addr, max(ep_out_mps, ep_in_mps)

    @classmethod
    async def from_device(cls, device, *,
                          logger: logging.Logger
                          ) -> "Transport":
        interface_index, ep_out_addr, ep_in_addr, mps = \
            cls.__find_interface(device)
        
        try:
            device.handle.detachKernelDriver(interface_index)
        except (usb1.USBErrorNotFound, usb1.USBErrorNotSupported,
                usb1.USBErrorAccess):
            pass
        device.handle.claimInterface(interface_index)

        ep_out = BulkOutEndpoint(device, ep_out_addr, mps)
        ep_in = BulkInEndpoint(device, ep_in_addr, mps)

        ep_out.resume()
        ep_in.resume()

        from ausb.exception import TransferTimeout
        try:
            while True:
                ep_in.read_sync(mps, timeout=20)
        except TransferTimeout:
            pass

        ep_out.resume()
        ep_in.resume()
        
        return cls(device, interface_index, ep_out, ep_in, mps, logger)

    async def write(self, data: bytes) -> None:
        await self.__ep_out.write(data)

    async def read(self, length: int) -> bytes:
        if length == 0:
            return b""
        out = bytearray()
        while len(out) < length:
            left = length - len(out)
            if self.__rx_leftovers:
                out.extend(self.__rx_leftovers[:left])
                self.__rx_leftovers = self.__rx_leftovers[left:]
            else:
                chunk = await self.__ep_in.read(self.__mps)
                out.extend(chunk[:left])
                self.__rx_leftovers = chunk[left:]
        return bytes(out)

class PipeLoopbackTester:
    def __init__(self, transport):
        self.transport = transport

    def blob_gen(self, x):
        return b''.join(x.to_bytes(4, "little") for x in range(x, x+1024))

    def blob_iterator(self):
        for i in range(1):
            yield self.blob_gen(i)

    def blob_diff(self, a, b, la, lb):
        for i in range(0, len(a), 16):
            print(f"{la:4s} {i:4x}: {a[i:i+16].hex()}")
            print(f"{lb:4s} {i:4x}: {b[i:i+16].hex()}")
        
    async def send_all(self):
        for blob in self.blob_iterator():
            #print(">", end = "", flush = True)
            await self.transport.write(blob)
            #print("<", end = "", flush = True)
        
    async def receive_all(self):
        start = time.time()
        transferred = 0
        for blob in self.blob_iterator():
            #print("+", end = "", flush = True)
            data = await self.transport.read(len(blob))
            if data != blob:
                self.blob_diff(blob, data, "OUT", "IN")
                raise ValueError()
            #print("-", end = "", flush = True)
            transferred += len(data)
        end = time.time()

        print(f"{transferred} bytes in {end - start:0.2f}s, {transferred / (end - start):g}B/s, {transferred / (end - start) * 8 * 2:g}bps fd")

    async def run(self):
        await asyncio.gather(
            self.send_all(),
            self.receive_all(),
        )
        
@base.cli.command(help="Loopback on pipe")
@click.option('-r', '--root', 'root', required=True,
              help="Component path (e.g. proby-9/jtag-pt)")
@click.pass_context
async def pipe_loopback(ctx, root):
    hw_root = ctx.obj.hw_root
    device = await ctx.obj.resolve(root)
    transport = await Transport.from_device(device.descriptor.open(),
                                            logger = logging.getLogger("pipe"))
    tester = PipeLoopbackTester(transport)

    await tester.run()
