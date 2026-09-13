"""Client side of the nsl_sdio CBOR transactor.

What travels to the device is a batch of commands and what comes back
is one item per command, in order.  Nothing here knows what a card is:
a batch is bus operations, and their answers are what the wires
carried.  The card lives in card.py.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass

import cbor2
from cbor2 import CBORSimpleValue, CBORTag, undefined

from acrobe.node import Node


class Blocks(bytes):
    """Data of a read, with the blocks it came in still apart.

    A read hands its blocks over as the chunks of an indefinite byte
    string, one chunk per block, so a run that dies part way says how
    far it got by how many chunks it put out.
    """

    chunks: list

    def __new__(cls, chunks):
        self = super().__new__(cls, b"".join(chunks))
        self.chunks = list(chunks)
        return self


class _Reader:
    """Enough of CBOR to read what the transactor answers.

    The tags of this protocol are small numbers, which are the ones
    CBOR gives a meaning of its own (a tag 1 is an epoch, a tag 2 a
    bignum).  Those meanings are not wanted here, so the answers are
    read rather than handed to a decoder that would apply them.
    """

    BREAK = object()

    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def __take(self, count: int) -> bytes:
        end = self.pos + count
        if end > len(self.data):
            raise ValueError("answer ends in the middle of an item")
        out = self.data[self.pos:end]
        self.pos = end
        return out

    def __head(self):
        """Major type of the next item and what its head carries."""
        first = self.__take(1)[0]
        major, info = first >> 5, first & 0x1f

        if info < 24:
            return major, info, info
        if info == 31:
            # Indefinite length, or the break that ends one
            return major, info, None
        if info > 27:
            raise ValueError(f"item head {first:#04x} means nothing")

        count = 1 << (info - 24)
        return major, info, int.from_bytes(self.__take(count), "big")

    def item(self):
        major, info, arg = self.__head()

        if major == 0:
            return arg
        if major == 1:
            return -1 - arg
        if major == 2:
            if info == 31:
                return Blocks(iter(self.__chunks()))
            return self.__take(arg)
        if major == 3:
            return self.__take(arg).decode("utf-8")
        if major == 4:
            return list(self.__items(arg if info != 31 else None))
        if major == 5:
            items = list(self.__items(2 * arg if info != 31 else None))
            return dict(zip(items[0::2], items[1::2]))
        if major == 6:
            return CBORTag(arg, self.item())

        # Major 7: what is left is the simple values
        if info == 31:
            return self.BREAK
        if arg == 20:
            return False
        if arg == 21:
            return True
        if arg == 22:
            return None
        if arg == 23:
            return undefined
        return CBORSimpleValue(arg)

    def __items(self, count):
        if count is None:
            while True:
                item = self.item()
                if item is self.BREAK:
                    return
                yield item
        else:
            for _ in range(count):
                yield self.item()

    def __chunks(self):
        while True:
            item = self.item()
            if item is self.BREAK:
                return
            yield item

    @property
    def done(self):
        return self.pos >= len(self.data)


# Commands, by the tag that carries them
TAG_COMMAND = 0
TAG_READ = 1
TAG_WRITE = 2
TAG_REPEAT = 3
TAG_HALF_CYCLE = 4
TAG_SAMPLE_PHASE = 5
TAG_WIDTH = 6
TAG_TIMEOUT = 7
TAG_CLOCK_RUN = 8
TAG_EVENTS = 9

# Commands that carry nothing, by the simple value that is them
SIMPLE_LINES = 1
SIMPLE_INFO = 2

# Answers, by the tag that carries them
RSP_ACK = 0
RSP_INFO = 1
RSP_LINES = 2
RSP_COMMAND = 3
RSP_READ = 4
RSP_WRITE = 5
RSP_EVENT = 6

# What a command asks a card to answer with
RESP_NONE = 0
RESP_SHORT = 1
RESP_SHORT_NO_CRC = 2
RESP_SHORT_BUSY = 3
RESP_LONG = 4

CMD_STATUS = ("ok", "timeout", "crc-error", "framing-error", "cancelled")
DAT_STATUS = ("ok", "timeout", "crc-error", "framing-error",
              "write-rejected", "write-failed", "underrun", "cancelled")

EVENT_KIND = ("card-interrupt", "card-inserted", "card-removed")


class TransactionError(Exception):
    """A command of a batch failed, which ended the batch."""

    def __init__(self, index, status, kind="command"):
        self.index = index
        self.status = status
        super().__init__(f"CMD{index} ended as {kind} {status}")


class Truncated(Exception):
    """The batch stopped short of its last command and said why."""


@dataclass(frozen=True, slots=True)
class Info:
    version: int
    clock_hz: int
    lane_count: int
    max_block_size: int


@dataclass(frozen=True, slots=True)
class Lines:
    card_present: bool
    cmd: bool
    dat: int
    busy: bool


@dataclass(frozen=True, slots=True)
class Response:
    """What a card answered a command with."""

    status: str
    index: int
    payload: bytes

    @property
    def ok(self):
        return self.status == "ok"

    @property
    def argument(self):
        """The 32 bits of a short answer, which is where a card puts
        its status, its operating conditions or its address."""
        return int.from_bytes(self.payload, "big")


@dataclass(frozen=True, slots=True)
class ReadResponse:
    response: Response
    data: Blocks
    data_status: str
    blocks: int


@dataclass(frozen=True, slots=True)
class WriteResponse:
    response: Response
    data_status: str
    blocks: int


@dataclass(frozen=True, slots=True)
class Event:
    kind: str
    asserted: bool


def half_cycle_m1(clock_hz: int, bus_hz: int) -> int:
    """Fabric cycles in a half period, minus one.

    Rounded so a bus clock comes out slower than asked for rather than
    faster, as nsl_sdio.link does it.
    """
    half = (clock_hz + 2 * bus_hz - 1) // (2 * bus_hz)
    return half - 1 if half else 0


def default_sample_phase(clock_hz: int, hcm1: int,
                         output_on_rising: bool = False) -> int:
    """Fabric cycle of a bus period to read a card at.

    The same choice nsl_sdio.link makes, and it has to stay the same:
    a card drives from 14 ns past the edge it answers until 2.5 ns
    past the next one, and this picks the cycle end closest to the
    middle of that.
    """
    output_delay_ps = 14000
    output_hold_ps = 2500

    cycle_ps = 1000000000 // (clock_hz // 1000)
    period_cycles = 2 * (hcm1 + 1)
    period_ps = period_cycles * cycle_ps

    valid_from_ps = output_delay_ps
    valid_to_ps = period_ps + output_hold_ps
    middle_ps = (valid_from_ps + valid_to_ps) // 2

    # Cycles between the edge a card answered and the end of phase
    # zero, which opens with a rising edge.
    offset = 1 if output_on_rising else hcm1 + 2

    candidate = ((middle_ps + cycle_ps // 2) // cycle_ps) - offset
    return candidate % period_cycles


class Batch:
    """A command stream under construction.

    Every command but a nop is answered by exactly one item, and the
    commands of a repeat's body are answered for by the repeat.
    """

    def __init__(self):
        self.items = []
        # What to make of each answer, in the order they come back
        self.expect = []
        # Commands of a repeat's body still to come, which answer
        # through their loop rather than for themselves
        self.body_left = 0

    def __len__(self):
        return len(self.items)

    def __append(self, item, expect):
        self.items.append(item)
        if self.body_left:
            self.body_left -= 1
        elif expect is not None:
            self.expect.append(expect)
        return self

    def nop(self, count: int = 1):
        """Padding, answered by nothing, which is how a host puts the
        payload of a write where a wider stream would rather have it."""
        for _ in range(count):
            self.__append(undefined, None)
        return self

    def delay(self, periods: int):
        """Bus periods to keep clocking for, which is how a card is
        given the clocks it wants before it answers anything."""
        return self.__append(periods, RSP_ACK)

    def command(self, index: int, argument: int = 0,
                response: int = RESP_SHORT):
        return self.__append(
            CBORTag(TAG_COMMAND, [response, index, argument]), RSP_COMMAND)

    def read(self, index: int, argument: int = 0, block_size: int = 512,
             block_count: int = 1, response: int = RESP_SHORT):
        return self.__append(
            CBORTag(TAG_READ, [response, index, argument,
                               block_size, block_count]), RSP_READ)

    def write(self, index: int, argument: int, data: bytes,
              block_size: int = 512, response: int = RESP_SHORT):
        return self.__append(
            CBORTag(TAG_WRITE, [response, index, argument,
                                block_size, bytes(data)]), RSP_WRITE)

    def repeat(self, body: int, attempts: int, mask: int, match: int):
        """Run the next `body` commands until the last of them answers
        with a payload the mask and match accept.

        A mask of zero accepts any payload, which leaves retrying
        until answered.  The whole loop answers once, with what the
        last command of its last round got.
        """
        self.__append(CBORTag(TAG_REPEAT, [body, attempts, mask, match]),
                      RSP_COMMAND)
        self.body_left = body
        return self

    def __setting(self, tag, value):
        return self.__append(CBORTag(tag, value), RSP_ACK)

    def set_half_cycle(self, value: int):
        return self.__setting(TAG_HALF_CYCLE, value)

    def set_sample_phase(self, value: int):
        return self.__setting(TAG_SAMPLE_PHASE, value)

    def set_width(self, lanes: int):
        return self.__setting(TAG_WIDTH, lanes)

    def set_timeout(self, periods: int):
        return self.__setting(TAG_TIMEOUT, periods)

    def set_clock_run(self, run: bool):
        return self.__setting(TAG_CLOCK_RUN, bool(run))

    def set_events(self, kinds: int):
        return self.__setting(TAG_EVENTS, kinds)

    def lines(self):
        return self.__append(CBORSimpleValue(SIMPLE_LINES), RSP_LINES)

    def info(self):
        return self.__append(CBORSimpleValue(SIMPLE_INFO), RSP_INFO)

    def encode(self) -> bytes:
        """The batch as it goes on the wire: an indefinite array, which
        is what lets a device act on a command before the batch ends."""
        body = b"".join(cbor2.dumps(item) for item in self.items)
        return b"\x9f" + body + b"\xff"


def decode(blob: bytes):
    """Answers and events of one batch, apart from each other."""
    items = _Reader(blob).item()
    answers = []
    events = []

    for item in items:
        if item is undefined:
            continue
        if not isinstance(item, CBORTag):
            raise ValueError(f"answer is not a tagged item: {item!r}")

        if item.tag == RSP_EVENT:
            kind, asserted = item.value
            events.append(Event(EVENT_KIND[kind], bool(asserted)))
        else:
            answers.append(item)

    return answers, events


def _response(fields):
    status, index, payload = fields
    return Response(CMD_STATUS[status], index, bytes(payload))


def interpret(item):
    """One answer, as what it says rather than as what it is made of."""
    if item.tag == RSP_ACK:
        return None
    if item.tag == RSP_INFO:
        return Info(*item.value)
    if item.tag == RSP_LINES:
        present, cmd, dat, busy = item.value
        return Lines(bool(present), bool(cmd), dat, bool(busy))
    if item.tag == RSP_COMMAND:
        return _response(item.value)
    if item.tag == RSP_READ:
        status, index, payload, data, dat_status, blocks = item.value
        return ReadResponse(_response((status, index, payload)),
                            data, DAT_STATUS[dat_status], blocks)
    if item.tag == RSP_WRITE:
        status, index, payload, dat_status, blocks = item.value
        return WriteResponse(_response((status, index, payload)),
                             DAT_STATUS[dat_status], blocks)
    raise ValueError(f"unknown answer tag {item.tag}")


class SdioTransactor(Node):
    """Runs batches against the transactor on the far end of a
    datagram channel."""

    def __init__(self, channel, name: str = "sdio"):
        Node.__init__(self, name)
        self.channel = channel
        self.events = []

    async def run(self, batch: Batch, strict: bool = True):
        """Sends a batch and gives back what each command answered.

        A command that fails ends a batch, so a short answer is the
        normal way a failure arrives: the last item names what failed.
        """
        blob = batch.encode()
        self.logger.protocol("cmd < %s", blob.hex())

        answer = await self.channel.exchange(blob)

        self.logger.protocol("rsp > %s", answer.hex())

        items, events = decode(answer)
        self.events += events
        for event in events:
            self.logger.info("event %s %s", event.kind,
                             "on" if event.asserted else "off")

        results = [interpret(item) for item in items]

        if strict and len(items) < len(batch.expect):
            last = results[-1] if results else None
            if isinstance(last, ReadResponse) and not last.response.ok:
                raise TransactionError(last.response.index, last.response.status)
            if isinstance(last, ReadResponse):
                raise TransactionError(last.response.index, last.data_status,
                                       "data")
            if isinstance(last, WriteResponse) and not last.response.ok:
                raise TransactionError(last.response.index, last.response.status)
            if isinstance(last, WriteResponse):
                raise TransactionError(last.response.index, last.data_status,
                                       "data")
            if isinstance(last, Response):
                raise TransactionError(last.index, last.status)
            raise Truncated(
                f"batch answered {len(items)} of {len(batch.expect)} commands")

        return results

    def submit(self, batch: Batch, strict: bool = True):
        """Sends a batch without waiting on it.

        What comes back is awaitable, so a caller with more to ask can
        keep several batches in the air: the one a device has not got
        to yet waits in the device rather than in a host holding the
        wire idle in between.
        """
        return asyncio.ensure_future(self.run(batch, strict))

    async def info(self) -> Info:
        return (await self.run(Batch().info()))[0]

    async def lines(self) -> Lines:
        return (await self.run(Batch().lines()))[0]
