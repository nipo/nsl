"""An SD memory card, as a batch of bus operations at a time.

The transactor below knows the bus and nothing else, so the command
set of a card, the sequence that brings one up and what its registers
mean all live here.
"""

from __future__ import annotations

import asyncio
from collections import deque
from dataclasses import dataclass

from acrobe.engine import Batcher
from acrobe.node import Node
from acrobe.protocol.memory import Interface, ReadBlob, WriteBlob

from transactor import (
    Batch, RESP_LONG, RESP_NONE, RESP_SHORT, RESP_SHORT_BUSY,
    RESP_SHORT_NO_CRC, SdioTransactor, TransactionError,
    default_sample_phase, half_cycle_m1,
)


BLOCK_SIZE = 512

# Commands of a memory card, by index
GO_IDLE_STATE = 0
ALL_SEND_CID = 2
SEND_RELATIVE_ADDR = 3
SET_BUS_WIDTH = 6          # application command
SELECT_CARD = 7
SEND_IF_COND = 8
SEND_CSD = 9
STOP_TRANSMISSION = 12
SEND_STATUS = 13
SET_BLOCKLEN = 16
READ_SINGLE_BLOCK = 17
READ_MULTIPLE_BLOCK = 18
SWITCH_FUNC = 6            # not the application command of the same index
WRITE_BLOCK = 24
WRITE_MULTIPLE_BLOCK = 25
SD_SEND_OP_COND = 41       # application command
APP_CMD = 55

# What CMD8 asks for and a card echoes back: 2.7-3.6 V, and a pattern
# that tells an answer from a bus that floated back high
IF_COND = 0x000001aa

# Operating conditions a host offers: 3.2-3.4 V, and high capacity
OCR_HOST = 0x40ff8000
OCR_BUSY = 1 << 31          # clear while a card is still powering up
OCR_CCS = 1 << 30           # set by a card addressed in blocks

# Bus clocks
INIT_HZ = 400000
DEFAULT_HZ = 25000000
HIGH_SPEED_HZ = 50000000

# What CMD6 is asked with: set what follows rather than ask about it,
# leave every group but the first alone, and put the first in its
# second function, which is the fast one.
SWITCH_TO_HIGH_SPEED = 0x80fffff1
SWITCH_STATUS_BYTES = 64


class CardError(Exception):
    pass


@dataclass(frozen=True, slots=True)
class Cid:
    """Who made a card and which one it is."""

    raw: bytes

    @property
    def manufacturer(self):
        return self.raw[0]

    @property
    def oem(self):
        return self.raw[1:3].decode("ascii", "replace")

    @property
    def name(self):
        return self.raw[3:8].decode("ascii", "replace")

    @property
    def revision(self):
        return f"{self.raw[8] >> 4}.{self.raw[8] & 0xf}"

    @property
    def serial(self):
        return int.from_bytes(self.raw[9:13], "big")

    @property
    def date(self):
        v = int.from_bytes(self.raw[13:15], "big")
        return (2000 + ((v >> 4) & 0xff), v & 0xf)

    def __str__(self):
        year, month = self.date
        return (f"{self.name!r} by {self.manufacturer:#04x}/{self.oem!r}"
                f" rev {self.revision} serial {self.serial:#010x}"
                f" from {month:02d}/{year}")


@dataclass(frozen=True, slots=True)
class Csd:
    """What a card says about itself, in either shape that has had."""

    raw: bytes

    @property
    def value(self):
        return int.from_bytes(self.raw, "big")

    def field(self, high, low):
        return (self.value >> low) & ((1 << (high - low + 1)) - 1)

    @property
    def version(self):
        return self.field(127, 126)

    async def high_speed(self):
        """Asks a card to take its clock twice as fast, and takes it
        there once it says it has.

        A card answers this on the data lines rather than in its
        response, so what says whether it did is a block: the function
        the first group ended up in.
        """
        result = (await self.sdio.run(
            Batch().read(SWITCH_FUNC, SWITCH_TO_HIGH_SPEED,
                         SWITCH_STATUS_BYTES, 1)))[0]

        if result.data_status != "ok":
            raise CardError(f"switch answered {result.data_status}")

        # Which function the access group ended up in, which is the
        # low half of the byte holding bits 383 to 376 of the block
        selected = result.data[16] & 0xf
        if selected != 1:
            raise CardError(
                f"card stayed in access function {selected}")

        batch = Batch()
        self.__bus(batch, HIGH_SPEED_HZ, output_on_rising=True)
        await self.sdio.run(batch)

        self.logger.info("bus at %d Hz", self.bus_hz)
        return self

    @property
    def block_count(self):
        if self.version == 0:
            # The first shape describes the array: so many units of so
            # many blocks of so many bytes.
            size = self.field(73, 62)
            mult = self.field(49, 47)
            read_len = self.field(83, 80)
            return (size + 1) << (mult + read_len - 7)
        # The second counts blocks in groups of 1024, which is all a
        # card over two gigabytes has to say about its size.
        return (self.field(69, 48) + 1) << 10

    @property
    def capacity(self):
        return self.block_count * BLOCK_SIZE


class SdCard(Node):
    """A card on the bus of a transactor.

    Identification and every access are batches: one round trip on the
    wire carries a whole sequence of bus operations.
    """

    def __init__(self, transactor: SdioTransactor, clock_hz: int = None,
                 lane_count: int = 4, name: str = "card"):
        Node.__init__(self, name)
        self.sdio = transactor
        self.clock_hz = clock_hz
        self.lane_count = lane_count

        self.rca = 0
        self.cid = None
        self.csd = None
        self.high_capacity = False
        self.width = 1
        self.bus_hz = 0

    def __bus(self, batch: Batch, bus_hz: int, output_on_rising: bool = False):
        """Puts the divider and the sampling point of a bus speed in a
        batch, which is what a card's clock is changed with.

        Which edge a card answers is not the same in every speed: at
        default speed it drives after the falling edge, and high speed
        moves that to the rising one, which is what buys the speed and
        what costs the margin.
        """
        hcm1 = half_cycle_m1(self.clock_hz, bus_hz)
        batch.set_half_cycle(hcm1)
        batch.set_sample_phase(
            default_sample_phase(self.clock_hz, hcm1, output_on_rising))
        self.bus_hz = self.clock_hz // (2 * (hcm1 + 1))

    def address(self, lba: int) -> int:
        """What a card wants a block called: a number for one
        addressed in blocks, an offset for one addressed in bytes."""
        return lba if self.high_capacity else lba * BLOCK_SIZE

    async def identify(self):
        """Brings a card from power-up to where it takes data.

        One batch does the whole sequence, the wait for a card to
        finish powering up included: a repeat runs the two commands
        that ask until the answer says it is done.
        """
        if self.clock_hz is None:
            self.clock_hz = (await self.sdio.info()).clock_hz

        batch = Batch()
        self.__bus(batch, INIT_HZ)
        batch.set_width(1)
        batch.set_timeout(1 << 20)
        # Idle is idle: the clock is taken away between transactions
        # and given back for each of them, which is what a host on
        # this bus does when it has nothing to say.
        batch.set_clock_run(False)

        # Clocks a card wants before it answers anything, which the
        # bus puts at 74 and cards ask more of.
        batch.delay(1000)

        batch.command(GO_IDLE_STATE, 0, RESP_NONE)
        batch.command(SEND_IF_COND, IF_COND)

        # Powering up takes as long as it takes, and asking is two
        # commands: the one that says the next is an application one,
        # and the one that offers what this host can supply.
        batch.repeat(2, 4096, OCR_BUSY, OCR_BUSY)
        batch.command(APP_CMD, 0)
        batch.command(SD_SEND_OP_COND, OCR_HOST, RESP_SHORT_NO_CRC)

        batch.command(ALL_SEND_CID, 0, RESP_LONG)
        batch.command(SEND_RELATIVE_ADDR, 0)

        # Settings and the wait answer too, and what is wanted is what
        # the last four commands got.
        if_cond, ocr, cid, rca = (await self.sdio.run(batch))[-4:]

        if if_cond.argument & 0xfff != (IF_COND & 0xfff):
            raise CardError(
                f"CMD8 echoed {if_cond.argument:#010x}, not {IF_COND:#010x}")

        self.high_capacity = bool(ocr.argument & OCR_CCS)
        self.cid = Cid(cid.payload)
        self.rca = rca.argument >> 16

        # From here a card answers to its address, and what it says
        # about itself can be read.
        batch = Batch()
        batch.command(SEND_CSD, self.rca << 16, RESP_LONG)
        batch.command(SELECT_CARD, self.rca << 16, RESP_SHORT_BUSY)
        batch.command(SET_BLOCKLEN, BLOCK_SIZE)

        if self.lane_count >= 4:
            batch.command(APP_CMD, self.rca << 16)
            batch.command(SET_BUS_WIDTH, 2)
            batch.set_width(4)

        # Default speed is as fast as a card goes without being asked
        self.__bus(batch, DEFAULT_HZ)

        csd = (await self.sdio.run(batch))[0]
        self.csd = Csd(csd.payload)
        self.width = 4 if self.lane_count >= 4 else 1

        self.logger.info("card %s", self.cid)
        self.logger.info("%d blocks of %d bytes (%.2f GB) over %d lines"
                         " at %d Hz",
                         self.csd.block_count, BLOCK_SIZE,
                         self.csd.capacity / 1e9, self.width, self.bus_hz)
        return self

    async def high_speed(self):
        """Asks a card to take its clock twice as fast, and takes it
        there once it says it has.

        A card answers this on the data lines rather than in its
        response, so what says whether it did is a block: the function
        the first group ended up in.
        """
        result = (await self.sdio.run(
            Batch().read(SWITCH_FUNC, SWITCH_TO_HIGH_SPEED,
                         SWITCH_STATUS_BYTES, 1)))[0]

        if result.data_status != "ok":
            raise CardError(f"switch answered {result.data_status}")

        # Which function the access group ended up in, which is the
        # low half of the byte holding bits 383 to 376 of the block
        selected = result.data[16] & 0xf
        if selected != 1:
            raise CardError(
                f"card stayed in access function {selected}")

        batch = Batch()
        self.__bus(batch, HIGH_SPEED_HZ, output_on_rising=True)
        await self.sdio.run(batch)

        self.logger.info("bus at %d Hz", self.bus_hz)
        return self

    @property
    def block_count(self):
        return self.csd.block_count if self.csd else 0

    async def read_blocks(self, lba: int, count: int = 1) -> bytes:
        """Blocks of a card, as one run.

        A card asked for one block answers it and then goes looking
        for the next command, and what it spends doing that is more
        than a block of data costs on the wire.  So a run of blocks is
        one command that keeps them coming and one that says when to
        stop, and only a single block is asked for by itself.
        """
        batch = Batch()
        if count == 1:
            batch.read(READ_SINGLE_BLOCK, self.address(lba), BLOCK_SIZE, 1)
        else:
            batch.read(READ_MULTIPLE_BLOCK, self.address(lba),
                       BLOCK_SIZE, count)
            batch.command(STOP_TRANSMISSION, 0, RESP_SHORT_BUSY)

        result = (await self.sdio.run(batch))[0]
        if result.data_status != "ok":
            raise CardError(
                f"blocks {lba}..{lba + count - 1} read as"
                f" {result.data_status} after {result.blocks}")
        return result.data

    def __read_batch(self, lba: int, count: int) -> Batch:
        batch = Batch()
        if count == 1:
            batch.read(READ_SINGLE_BLOCK, self.address(lba), BLOCK_SIZE, 1)
        else:
            batch.read(READ_MULTIPLE_BLOCK, self.address(lba),
                       BLOCK_SIZE, count)
            batch.command(STOP_TRANSMISSION, 0, RESP_SHORT_BUSY)
        return batch

    async def read_run(self, lba: int, count: int,
                       per_batch: int = 64, depth: int = 3) -> bytes:
        """A long run of blocks, asked for several runs at a time.

        A card is ready for the next run as soon as it has finished
        the one before, so what is worth avoiding is the wait between
        the two: with the next batch already in the device, it starts
        where the last one ended rather than a round trip later.
        """
        out = bytearray()
        flight = deque()
        issued = 0

        while issued < count or flight:
            while issued < count and len(flight) < depth:
                take = min(per_batch, count - issued)
                flight.append((lba + issued, take,
                               self.sdio.submit(
                                   self.__read_batch(lba + issued, take))))
                issued += take

            first, take, pending = flight.popleft()
            result = (await pending)[0]
            if result.data_status != "ok":
                raise CardError(
                    f"blocks {first}..{first + take - 1} read as"
                    f" {result.data_status} after {result.blocks}")
            out += result.data

        return bytes(out)

    def __write_batch(self, lba: int, data: bytes) -> Batch:
        batch = Batch()
        if len(data) == BLOCK_SIZE:
            batch.write(WRITE_BLOCK, self.address(lba), data, BLOCK_SIZE)
        else:
            batch.write(WRITE_MULTIPLE_BLOCK, self.address(lba),
                        data, BLOCK_SIZE)
            batch.command(STOP_TRANSMISSION, 0, RESP_SHORT_BUSY)
        return batch

    async def write_blocks(self, lba: int, data: bytes):
        """Blocks into a card, as one run.

        A card takes a run of blocks the same way it gives one: one
        command that keeps them coming and one that says when to stop.
        What it answers with is how many it stored, and a run that
        dies part way says where.
        """
        if len(data) % BLOCK_SIZE or not data:
            raise ValueError("writes go by whole blocks")

        result = (await self.sdio.run(self.__write_batch(lba, data)))[0]
        if result.data_status != "ok":
            raise CardError(
                f"blocks {lba}..{lba + len(data) // BLOCK_SIZE - 1} written as"
                f" {result.data_status} after {result.blocks}")
        return result.blocks

    async def write_run(self, lba: int, data: bytes,
                        per_batch: int = 64, depth: int = 2):
        """A long run of blocks, given several runs at a time.

        As with reading, what is worth avoiding is the wait between
        one run and the next: a card storing a block is busy whatever
        the host does, so the next batch belongs in the device before
        it is needed.
        """
        if len(data) % BLOCK_SIZE or not data:
            raise ValueError("writes go by whole blocks")

        count = len(data) // BLOCK_SIZE
        flight = deque()
        issued = 0
        stored = 0

        while issued < count or flight:
            while issued < count and len(flight) < depth:
                take = min(per_batch, count - issued)
                chunk = data[issued * BLOCK_SIZE:(issued + take) * BLOCK_SIZE]
                flight.append((lba + issued, take,
                               self.sdio.submit(
                                   self.__write_batch(lba + issued, chunk))))
                issued += take

            first, take, pending = flight.popleft()
            result = (await pending)[0]
            if result.data_status != "ok":
                raise CardError(
                    f"blocks {first}..{first + take - 1} written as"
                    f" {result.data_status} after {result.blocks}")
            stored += result.blocks

        return stored


class SdMemory(Interface, Batcher, Node):
    """A card as a flat address space.

    Blocks are what a card moves, so a read of a few bytes reads the
    blocks they sit in and cuts what was asked for out of them.
    """

    ops = frozenset({ReadBlob, WriteBlob})

    def __init__(self, card: SdCard, name: str = "memory"):
        Batcher.__init__(self)
        Node.__init__(self, name)
        self.card = card

    @property
    def size(self):
        return self.card.block_count * BLOCK_SIZE

    async def flush_ops(self, batch):
        # Every op is a round trip of its own; running them from a task
        # keeps the batcher's lock free while the wire is busy.
        asyncio.ensure_future(self.__run(list(batch)))

    async def __run(self, batch):
        for op, future in batch:
            try:
                if isinstance(op, ReadBlob):
                    result = await self.__read(op.addr, op.size)
                else:
                    result = await self.__write(op.addr, op.data)
            except BaseException as exc:  # noqa: BLE001 — forward it
                if future is not None and not future.done():
                    future.set_exception(exc)
                continue
            if future is not None and not future.done():
                future.set_result(result)

    async def __read(self, addr, size):
        first = addr // BLOCK_SIZE
        last = (addr + size - 1) // BLOCK_SIZE
        blob = await self.card.read_run(first, last - first + 1)
        start = addr - first * BLOCK_SIZE
        return blob[start:start + size]

    async def __write(self, addr, data):
        if addr % BLOCK_SIZE or len(data) % BLOCK_SIZE:
            raise CardError(
                "a card takes whole blocks, so a write has to be one")
        await self.card.write_run(addr // BLOCK_SIZE, data)
        return None
