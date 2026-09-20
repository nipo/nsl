"""Which slots of the wire the pads hold, and which they let go of.

Run with::

  acrobe run drivemap.py [resource-path] [dqs-invert] [dq-lead] [dqs-lead]

A readback cannot tell a pad driven high from a pad nobody is driving:
both read as ones.  What tells them apart is repetition.  A driven slot
carries the same level every pass, because the same word is serialised
onto it every pass; a released slot settles wherever the bus and the
receiver leave it, and that resolves one way or the other pass by pass.
So a slot read twelve times over is either a level or a coin, and which
it is says whether the pad was holding it.

The capture picked out at read offset N holds the eight wire slots N to
N+7, slot zero first.  Sweeping the offset across a window and keeping
slot zero of each reading gives one reading of every slot the sweep
starts on, all taken at the same place in a word; the remaining seven
slots of the last offset carry the window to its end.

The strobe is caught on the pin it leaves by, through a delay line and
a capture identical to the data pins', and picked out of that capture
with the same offset, so the two rows printed under each other are the
same slots of the same wire.

Run at both settings of the termination, because termination is the
one thing outside the pads that changes what a released slot settles
at.  The two enable leads default to the figures already measured and
may be given on the command line, which is how they were measured in
the first place: the lead that holds the pad over exactly the slots
its burst asks for is the one this map shows a steady level at from
the preamble to the postamble and a coin either side.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from taps import Line
from walk import Walk


class Window:
    """The wire slots one sweep of read offsets covers.

    Centred on the record's own read offset, a word either side of it,
    which is where a burst timed against its own command can be: the
    slip spans a word and the preamble and postamble a pair of slots
    each.  A board whose offset has not been measured has nothing to
    centre on, so the record's placeholder is what this follows.
    """

    OFFSETS = tuple(range(max(Walk.OFFSET - 10, 0),
                          min(Walk.OFFSET + 14, Walk.OFFSET_COUNT)))
    FIRST = OFFSETS[0]
    LAST = OFFSETS[-1] + 7

    @classmethod
    def slots(cls):
        return range(cls.FIRST, cls.LAST + 1)

    @classmethod
    def source(cls, slot):
        """The offset a slot is taken from, and its place in that word."""
        if slot <= cls.OFFSETS[-1]:
            return slot, 0
        return cls.OFFSETS[-1], slot - cls.OFFSETS[-1]


class Reading:
    """Every pass of one sweep, kept by the offset it was taken at."""

    UNSTEADY = "x"

    def __init__(self):
        self.words = {}
        self.strobes = {}

    def add(self, offset, word, strobe):
        self.words.setdefault(offset, []).append(word)
        self.strobes.setdefault(offset, []).append(strobe)

    @staticmethod
    def steady(values):
        """The value every pass agreed on, or None."""
        first = values[0]
        return first if all(value == first for value in values) else None

    def strobe_passes(self, slot, lane):
        offset, place = Window.source(slot)
        return [(strobe[lane] >> (7 - place)) & 1
                for strobe in self.strobes[offset]]

    def data_passes(self, slot, lane):
        """One byte lane of one slot, a reading a pass.

        A cycle is laid out a lane at a time inside a slot, so lane l
        of slot s is byte 2s + l of the word.
        """
        offset, place = Window.source(slot)
        byte = Walk.LANES * place + lane
        return [(word >> (8 * byte)) & 0xff for word in self.words[offset]]

    def strobe_map(self, lane):
        """One character a slot: the level it held, or that it held none."""
        marks = []
        for slot in Window.slots():
            bit = self.steady(self.strobe_passes(slot, lane))
            marks.append(self.UNSTEADY if bit is None else str(bit))
        return "".join(marks)

    def data_map(self, lane):
        """One byte a slot, or a mark where the passes disagreed."""
        cells = []
        for slot in Window.slots():
            byte = self.steady(self.data_passes(slot, lane))
            cells.append(2 * self.UNSTEADY if byte is None
                         else f"{byte:02x}")
        return cells

    @staticmethod
    def extent(marks, wanted):
        """The first and last slot a mark of the wanted kind is at."""
        hits = [slot for slot, mark in zip(Window.slots(), marks)
                if wanted(mark)]
        if not hits:
            return None
        return hits[0], hits[-1]


class DriveMap:
    SETTLE_SECONDS = 0.05
    PASSES = 12
    VALUE = 0x40
    SLIP = Walk.SLIP
    # The tap every readback is sampled at.  On the read side alone, so
    # it cannot change what the pads did; it has to be the same from
    # map to map for the maps to be read against each other.
    TAP = 0
    # Termination at the part, both ways round.
    ROUNDS = (1, 0)

    def __init__(self, path, invert, dq_lead, dqs_lead):
        self.session = Session(path)
        self.panel = None
        self.line = None
        self.invert = invert
        self.dq_lead = dq_lead
        self.dqs_lead = dqs_lead

    async def capture(self):
        """One pass: the captured cycle as a word, and each lane's strobe.

        Taken in one burst of the status region, so the data words and
        the strobe words are the same capture rather than several.
        """
        status = (await self.panel.snapshot())["status"]
        word = 0
        for index in range(Walk.DATA_WORDS):
            word |= status[f"mpr_{index}"] << (32 * index)
        strobe = [status[f"strobe_word_{lane}"]
                  for lane in range(Walk.LANES)]
        return word, strobe

    async def sweep(self):
        """Every offset of the window, each read over every pass."""
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("poke_value", self.VALUE)
        await asyncio.sleep(0.05)
        await self.panel.control_write("poke", 1)
        await asyncio.sleep(0.2)

        reading = Reading()
        for offset in Window.OFFSETS:
            await self.panel.control_write("offset", offset)
            await asyncio.sleep(self.SETTLE_SECONDS)
            for _ in range(self.PASSES):
                word, strobe = await self.capture()
                reading.add(offset, word, strobe)

        await self.panel.control_write("poke", 0)
        return reading

    def report(self, odt, reading):
        print(f"\n=== dq_lead {self.dq_lead}, dqs_lead {self.dqs_lead},"
              f" dqs_invert {self.invert}, odt {odt},"
              f" poke {self.VALUE:#04x},"
              f" slip {self.SLIP}, tap {self.TAP},"
              f" {self.PASSES} passes")

        half = (Window.LAST + 1 - Window.FIRST) // 2
        for lane in range(Walk.LANES):
            marks = reading.strobe_map(lane)
            cells = reading.data_map(lane)
            print(f"  lane {lane}")
            print(f"    strobe slots {Window.FIRST}..{Window.LAST}:"
                  f"  {marks}")
            print(f"    data   slots {Window.FIRST}"
                  f"..{Window.FIRST + half - 1}:  "
                  + " ".join(cells[:half]))
            print(f"    data   slots {Window.FIRST + half}"
                  f"..{Window.LAST}:  " + " ".join(cells[half:]))

            self.extents(f"strobe {lane}", marks,
                         lambda mark: mark != Reading.UNSTEADY,
                         lambda mark: mark == Reading.UNSTEADY)
            self.extents(f"data {lane}", cells,
                         lambda cell: cell != 2 * Reading.UNSTEADY,
                         lambda cell: cell == 2 * Reading.UNSTEADY)

    @staticmethod
    def extents(what, marks, is_steady, is_unsteady):
        steady = Reading.extent(marks, is_steady)
        unsteady = Reading.extent(marks, is_unsteady)
        if steady is None:
            print(f"    the {what} was the same every pass at no slot")
        else:
            print(f"    the {what} was the same every pass over slots"
                  f" {steady[0]} to {steady[1]}")
        if unsteady is None:
            print(f"    the {what} never changed from pass to pass")
        else:
            print(f"    the {what} changed from pass to pass over slots"
                  f" {unsteady[0]} to {unsteady[1]}")

    async def setup(self):
        for name in ("run", "level", "mpr", "poke", "tdqs"):
            await self.panel.control_write(name, 0)
        await Walk.take_panel(self.panel, slip=self.SLIP,
                              dq_lead=self.dq_lead, dqs_lead=self.dqs_lead,
                              invert=self.invert)
        # The capture is announced on the write, so what it holds is
        # this design's own burst on its own pins.
        await self.panel.control_write("snoop", 1)

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")
        self.line = Line(self.panel)
        await self.setup()

        if not await self.line.goto(self.TAP):
            print("the delay lines never reported their mark:"
                  f" tap {self.TAP} is measured from an unknown one")
        else:
            print(f"every readback's delay line is at tap {self.TAP}")

        for odt in self.ROUNDS:
            await self.panel.control_write("odt", odt)
            await asyncio.sleep(0.1)
            self.report(odt, await self.sweep())

        await self.panel.control_write("snoop", 0)
        await Walk.leave_panel(self.panel)
        return 0


async def main():
    args = list(sys.argv[1:])
    path = Walk.DEFAULT_PATH
    if args and not args[0].isdigit():
        path = args.pop(0)
    invert = int(args[0]) if args else Walk.DQS_INVERT
    dq_lead = int(args[1]) if len(args) > 1 else Walk.DQ_LEAD
    dqs_lead = int(args[2]) if len(args) > 2 else Walk.DQS_LEAD
    await DriveMap(path, invert, dq_lead, dqs_lead).run()
