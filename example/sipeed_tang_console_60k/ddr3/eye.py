"""Where the read eye is, measured on data rather than searched for.

Run with::

  acrobe run eye.py [resource-path] [part=probe,poke,mpr]

Training maps the read plane with the probe walker and sits in the
middle of the widest run of clean taps it finds.  This says the same
thing at more length, and from two more directions, so that a plane
whose eye is in the wrong place can be read for which half of the path
put it there.

Three maps, each with a tap of the delay line in every column and a
read offset on every row, and a number in every cell saying how much
of a burst came back wrong there:

* the probe walker, which is the write path and the read path
  together, sixteen beats written and read back inside one open row,
  three passes a cell so that a cell says whether the point is steady
  as well as whether it answers;

* a burst poked straight at the DFI, which is one write and one read
  with no core, adapter or walker in the way;

* the multi-purpose register, which is the read path alone against a
  pattern the part holds, and owes nothing to a write.

The taps only ever move the sampling instant, so the write path is the
same at every column of every map: a column that is bad in the first
two maps and good in the third has its trouble in the write, and a
column bad in all three has it in the read.

The line, the tables and the reading of their runs are ``readmap.py``,
which the training in ``walk.py`` maps the same plane with: the tables
are by tap and not by tick, and runs of clean taps are counted without
wrapping past the end of the line.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from mpr import WANTED
from readmap import Line, Probe, Table
from walk import Walk


class Eye:
    # The maps that need the sequencer rather than a walker are read at
    # the offsets the part answered at, and one either side.  Centred
    # on the record's read offset until it has been measured here.
    DATA_OFFSETS = tuple(range(max(Walk.OFFSET - 2, 0),
                               min(Walk.OFFSET + 2, Walk.OFFSET_COUNT)))
    # A controller cycle is sixteen bytes on this part: eight slots of
    # two byte lanes.
    BEATS = Walk.BEAT_BYTES
    # Three passes a cell: whether a point answers and whether it keeps
    # answering are different questions, and the second is the one a
    # single pass cannot ask.
    PASSES = 3
    POKE_SETTLE = 0.3
    POKE_SELECT = 0.05
    MPR_SETTLE = 0.15
    POKE_VALUE = 0x40
    # How many times the best point of the first map is asked again, to
    # say whether a point that is clean stays clean.
    REPEATS = 10
    PARTS = ("probe", "poke", "mpr")

    def __init__(self, path, parts=PARTS):
        self.session = Session(path)
        self.parts = parts
        self.panel = None
        self.line = None
        self.probe = None
        self.tables = {}

    @staticmethod
    def parse(args):
        """The resource path and which maps to make."""
        path = Walk.DEFAULT_PATH
        parts = Eye.PARTS
        for arg in args:
            key, sep, value = arg.partition("=")
            if sep and key == "part":
                parts = tuple(value.split(","))
            elif not sep:
                path = arg

        return path, parts

    # -- the panel ---------------------------------------------------------

    async def setup(self):
        """The board record on the panel, and the sequencer quiet.

        Written here rather than left wherever another script put it,
        so a run says the same thing whatever ran before it.
        """
        for name in ("run", "level", "mpr", "poke", "tdqs", "snoop"):
            await self.panel.control_write(name, 0)
        # The maps move the read offset and the delay line, so the PHY
        # reads the panel's copy of the record while they run.
        await Walk.take_panel(self.panel)
        await self.panel.control_write("poke_ap", 0)
        await self.panel.control_write("odt", 1)
        await self.panel.control_write("poke_value", self.POKE_VALUE)

    async def answer(self):
        """The whole cycle of the last beat the sequencer caught."""
        return await Walk.wide(self.panel, "mpr")

    @staticmethod
    def bytes_of(word):
        return Walk.burst_bytes(word)

    # -- the three measurements --------------------------------------------

    async def poke_cell(self, offset):
        """One burst written and read back, straight at the DFI."""
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("offset", offset)
        await asyncio.sleep(self.POKE_SELECT)
        await self.panel.control_write("poke", 1)
        await asyncio.sleep(self.POKE_SETTLE)
        got = self.bytes_of(await self.answer())
        await self.panel.control_write("poke", 0)

        want = [(self.POKE_VALUE + i) & 0xff for i in range(self.BEATS)]
        bad = sum(1 for a, b in zip(want, got) if a != b)
        return str(bad), bad

    async def mpr_cell(self, offset):
        """One read of the pattern the part holds, either way up.

        Which of the two beats comes first depends on where the burst
        is caught, so both orders count.
        """
        await self.panel.control_write("offset", offset)
        await asyncio.sleep(self.MPR_SETTLE)
        got = self.bytes_of(await self.answer())

        bad = min(sum(1 for a, b in zip(self.bytes_of(wanted), got) if a != b)
                  for wanted in WANTED)
        return str(bad), bad

    # -- the sweep ---------------------------------------------------------

    async def probe_map(self):
        table = self.probe.table(stride=Walk.COARSE_STRIDE)
        await self.panel.control_write("mpr", 0)
        await self.panel.control_write("poke", 0)
        await table.fill(self.line, self.probe.cell)
        return table

    async def poke_map(self):
        table = Table("poke", "a burst poked straight at the DFI",
                      f"bad bytes of {self.BEATS} against"
                      f" {self.POKE_VALUE:#04x} counting up, one poke a cell",
                      self.DATA_OFFSETS,
                      range(0, Line.TAP_COUNT, Walk.COARSE_STRIDE))
        await self.panel.control_write("run", 0)
        await self.panel.control_write("mpr", 0)
        await table.fill(self.line, self.poke_cell)
        return table

    async def mpr_map(self):
        table = Table("mpr",
                      "the multi-purpose register, the read path alone",
                      f"bad bytes of {self.BEATS} against the alternating"
                      " pattern, either way up",
                      self.DATA_OFFSETS,
                      range(0, Line.TAP_COUNT, Walk.COARSE_STRIDE))
        await self.panel.control_write("run", 0)
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("mpr", 1)
        await asyncio.sleep(0.5)
        count = await self.panel.status_read("mpr_count")
        if not count:
            print("  the part is answering nothing at all: the read command"
                  " is not reaching it, or the capture never fires")
        await table.fill(self.line, self.mpr_cell)
        await self.panel.control_write("mpr", 0)
        await asyncio.sleep(0.2)
        return table

    # -- what the maps say together ----------------------------------------

    def side_by_side(self):
        """The three widths against each other, offset by offset."""
        print("--- the three widths side by side, clean taps then taps with"
              " at most one error")
        head = "  ".join(f"{name:>16}" for name in self.PARTS)
        print(f" offset | {head}")
        offsets = sorted({offset for table in self.tables.values()
                          for offset in table.offsets})
        for offset in offsets:
            cells = []
            for name in self.PARTS:
                table = self.tables.get(name)
                if table is None or offset not in table.offsets:
                    cells.append(f"{'-':>16}")
                    continue
                clean = table.run_of(offset, 0)[0]
                most = table.run_of(offset, 1)[0]
                cells.append(f"{clean:>7} {most:>8}")
            print(f"     {offset:>2} | " + "  ".join(cells))

    async def repeat(self, table):
        """The best point of the first map, asked ten times over."""
        offset, tap, length, limit = table.best()
        if offset is None:
            print("--- no point of the probe map is worth asking again:"
                  " no run of even one error wide anywhere")
            return

        what = "clean" if limit == 0 else "at most one error"
        print(f"--- the probe walker {self.REPEATS} times at offset"
              f" {offset}, tap {tap}")
        print(f"    the middle of the widest run of {what}: {length} taps")

        await self.panel.control_write("mpr", 0)
        await self.panel.control_write("poke", 0)
        if not await self.line.goto(tap):
            print("    the delay lines never reported their mark: this is"
                  " measured from an unknown tap")

        errors = [await self.probe.once(offset) for _ in range(self.REPEATS)]
        shown = " ".join("--" if count is None else str(count)
                         for count in errors)
        print(f"    bad beats of {Probe.BEATS}, one pass a figure:"
              f" {shown}")
        clean = sum(1 for count in errors if count == 0)
        print(f"    {clean} of {self.REPEATS} passes came back whole")

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")
        self.line = Line(self.panel)
        self.probe = Probe(self.panel, Walk.PROBE, self.PASSES)

        if not await self.panel.status_read("ready"):
            print("controller: not ready, the power-up sequence has not run")
            return 1

        await self.setup()

        makers = {"probe": self.probe_map, "poke": self.poke_map,
                  "mpr": self.mpr_map}
        for name in self.PARTS:
            if name not in self.parts:
                continue
            self.tables[name] = await makers[name]()
            self.tables[name].render()
            print()
            self.tables[name].summarise()
            print()

        if len(self.tables) > 1:
            self.side_by_side()
            print()

        if "probe" in self.tables:
            await self.repeat(self.tables["probe"])

        await self.panel.control_write("run", 0)
        await Walk.leave_panel(self.panel)
        return 0


async def main():
    path, parts = Eye.parse(sys.argv[1:])
    if await Eye(path, parts).run():
        raise SystemExit(1)
