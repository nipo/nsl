"""Where our data transitions sit against our own strobe edges, in delay taps.

Run with::

  acrobe run taps.py [resource-path]

The ruler places our burst and our strobe in slots of the fast clock,
and cannot do better than one of them: the quarter period between the
data and the strobe is half a slot.  The delay line every readback
comes through is finer.  Every data pin and the strobe pin sit behind
one, all stepped together by the panel's tick, and a tap is 78 ps
against the 200 MHz reference.

Walking the taps moves the sampling instant against a waveform that
does not move.  Two things move under it: the tap where the captured
burst shifts by a slot is the sample point crossing a data transition,
and the tap where the strobe's driven run shifts by a slot is the same
point crossing the strobe's own edges.  The taps between those two,
times 78 ps, are the distance between our data transitions and our
strobe edges at the pin.  The quarter period would be about eight.

Two things the line does that a sweep has to allow for.  The primitive
is stepped with its increment tied low, so each tick takes the tap
*down* and the mark is the longest way round rather than the shortest:
a run of n ticks from the mark leaves the line at tap 32 - n, and the
table below is by tap and not by tick.  And the strobe, sampled every
slot when its own edges are a slot apart, resolves one way for a whole
burst rather than reading as a toggle, and which way it resolves
changes from pass to pass; so the strobe word is taken several times
at each tap and the slots it was ever high in are what the run is read
from.

The sweep is run at two poke values, so a reading that owes anything
to the value it was taken at says so.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from ruler import TOGGLING, Ruler
from walk import Walk


class Line:
    """The delay line every readback comes through, and where it sits.

    One line per data pin and one on the strobe, all stepped together
    by the panel's tick.  A tick makes the line one tap longer and the
    line wraps past its last tap, so tap n is n ticks from the mark and
    the way to a known tap is through the mark.
    """

    TAP_COUNT = 32
    TAP_PS = 78
    SETTLE_SECONDS = 0.02

    def __init__(self, panel):
        self.panel = panel
        self.tick = 0

    @classmethod
    def tap_of(cls, ticks):
        """The tap a run of ticks from the mark leaves the line at."""
        return ticks % cls.TAP_COUNT

    async def step(self):
        self.tick ^= 1
        await self.panel.control_write("tick", self.tick)
        await asyncio.sleep(self.SETTLE_SECONDS)

    async def home(self):
        return await self.panel.status_read("delay_mark") == 0xff

    async def rewind(self):
        for _ in range(2 * self.TAP_COUNT + 2):
            if await self.home():
                return True
            await self.step()

        return False

    async def goto(self, tap):
        """Sit at one tap, counted from the mark."""
        if not await self.rewind():
            return False

        for _ in range(tap % self.TAP_COUNT):
            await self.step()

        return True


class Point:
    """One tap of the line, and everything read there."""

    def __init__(self, tap, row, strobes):
        self.tap = tap
        self.row = row
        self.strobes = strobes

    def data(self, offset):
        return self.row[offset]

    def ever_high(self):
        """The slots the strobe was high in over any of the passes."""
        word = 0
        for strobe in self.strobes:
            word |= strobe
        return word

    def run_start(self):
        """Slots from the window's start to the strobe's driven run."""
        word = f"{self.ever_high():08b}"
        if "1" not in word:
            return None
        return word.index("1")

    def toggling(self):
        return [f"{strobe:08b}" for strobe in self.strobes
                if f"{strobe:08b}" in TOGGLING]


class Taps:
    SETTLE_SECONDS = 0.05
    # The strobe resolves one way or the other for a whole pass, so
    # one reading of it says nothing about where its edges are and
    # several do.
    STROBE_READS = 5
    # The slots the ruler put the burst and the strobe in, and a slot
    # either side of them.
    OFFSETS = tuple(range(40, 50))
    HOME = 41
    VALUES = (0x40, 0x10)

    def __init__(self, path):
        self.session = Session(path)
        self.panel = None
        self.line = None

    async def answer(self):
        """The eight captured bytes, earliest slot first, and the strobe."""
        low = await self.panel.status_read("mpr_low")
        high = await self.panel.status_read("mpr_high")
        word = (high << 32) | low
        strobe = await self.panel.status_read("strobe_word")
        return [(word >> (8 * i)) & 0xff for i in range(8)], strobe

    async def read_point(self, tap):
        """One capture at each offset, and the strobe over several."""
        row = {}
        strobes = []
        for offset in self.OFFSETS:
            await self.panel.control_write("offset", offset)
            await asyncio.sleep(self.SETTLE_SECONDS)
            got, strobe = await self.answer()
            row[offset] = got
            if offset == self.HOME:
                strobes.append(strobe)

        await self.panel.control_write("offset", self.HOME)
        for _ in range(self.STROBE_READS - 1):
            await asyncio.sleep(self.SETTLE_SECONDS)
            strobes.append(await self.panel.status_read("strobe_word"))

        return Point(tap, row, strobes)

    async def sweep(self, value):
        """Every tap of the line, at one poke value."""
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("poke_value", value)
        await asyncio.sleep(0.05)
        await self.panel.control_write("poke", 1)
        await asyncio.sleep(0.2)

        points = []
        for ticks in range(Line.TAP_COUNT):
            points.append(await self.read_point(Line.tap_of(ticks)))
            await self.line.step()

        await self.panel.control_write("poke", 0)
        return sorted(points, key=lambda point: point.tap)

    @staticmethod
    def compact(got):
        return "".join(f"{b:02x}" for b in got)

    @staticmethod
    def spaced(got):
        return " ".join(f"{b:02x}" for b in got)

    @staticmethod
    def strobes(point):
        seen = []
        for strobe in point.strobes:
            word = f"{strobe:08b}"
            if seen and seen[-1][0] == word:
                seen[-1][1] += 1
            else:
                seen.append([word, 1])
        return " ".join(f"{word}x{times}" for word, times in seen)

    @staticmethod
    def first_slot(point, value):
        """The offset the burst is whole and in order at, if any."""
        want = [(value + i) & 0xff for i in range(8)]
        for offset, got in point.row.items():
            if got == want:
                return offset

        return None

    @staticmethod
    def out_of_order(point, value):
        """Where the burst is found in some other order, and which."""
        for offset, got in point.row.items():
            how = Ruler.shape(got, value)
            if how is not None and how != "in order":
                return offset, how

        return None, None

    @staticmethod
    def bands(readings):
        """Runs of consecutive taps a reading holds over."""
        bands = []
        for tap, value in readings:
            if bands and bands[-1][2] == value:
                bands[-1][1] = tap
            else:
                bands.append([tap, tap, value])

        return bands

    @staticmethod
    def crossing(taps, values):
        """Where a reading changes, as the tap between the two it holds at.

        A crossing the pins disagree over spreads into a band of taps
        holding neither value; the midpoint of that band is as fine as
        this gets.
        """
        crossings = []
        last = None
        for tap, value in zip(taps, values):
            if value is None:
                continue
            if last is not None and value != last[1]:
                crossings.append(((last[0] + tap) / 2, last[1], value))
            last = (tap, value)

        return crossings

    def table(self, value, points):
        print(f"--- poke value {value:#04x}, capture announced on the write")
        print(" tap  data at 41                strobe at 41,"
              f" {self.STROBE_READS} passes"
              "              at 40             at 42")
        for point in points:
            print(f" {point.tap:>3}  {self.spaced(point.data(self.HOME))}"
                  f"   {self.strobes(point):<44}"
                  f"  {self.compact(point.data(40))}"
                  f"  {self.compact(point.data(42))}")
        print()

    def summarise(self, value, points):
        print(f"  value {value:#04x}: summary")
        data = self.summarise_data(value, points)
        strobe = self.summarise_strobe(points)

        if not data or not strobe:
            print("    no distance to take: one of the two edges is not"
                  " crossed over this line")
        else:
            for where, was, now in data:
                near = min(strobe, key=lambda cross: abs(cross[0] - where))
                gap = near[0] - where
                print(f"    data crossing at tap {where}, nearest strobe"
                      f" crossing at tap {near[0]}: {gap:+.1f} taps,"
                      f" {gap * Line.TAP_PS:+.0f} ps")

            order = sorted([(where, "data") for where, _, _ in data]
                           + [(where, "strobe") for where, _, _ in strobe])
            print("    every crossing in tap order, and the step between:")
            last = None
            for where, what in order:
                if last is None:
                    print(f"      {what:>6} at tap {where}")
                else:
                    gap = where - last[0]
                    print(f"      {what:>6} at tap {where}"
                          f"   {last[1]} -> {what}: {gap:.1f} taps,"
                          f" {gap * Line.TAP_PS:.0f} ps")
                last = (where, what)

        self.summarise_toggling(points)
        print()

    def summarise_data(self, value, points):
        """Where the burst sits at each tap, and where that changes."""
        taps = [point.tap for point in points]
        slots = [self.first_slot(point, value) for point in points]

        missing = [tap for tap, slot in zip(taps, slots) if slot is None]
        if not missing:
            print("    the burst is whole and in order at every tap")
        else:
            print(f"    the burst is in no order at all at taps {missing}")
            for point in points:
                if self.first_slot(point, value) is not None:
                    continue
                offset, how = self.out_of_order(point, value)
                if offset is None:
                    print(f"      tap {point.tap}: at no offset,"
                          " in any order")
                else:
                    print(f"      tap {point.tap}: at offset {offset}, {how}")

        print("    first slot by tap: "
              + " ".join("--" if slot is None else f"{slot}"
                         for slot in slots))

        crossings = self.crossing(taps, slots)
        if not crossings:
            print("    the burst's first slot never changes over a whole"
                  " turn of the line")
        for where, was, now in crossings:
            print(f"    the burst's first slot goes {was} -> {now}"
                  f" at tap {where}")

        return crossings

    def summarise_strobe(self, points):
        """Where the strobe's run sits at each tap, and where that changes."""
        taps = [point.tap for point in points]
        starts = [point.run_start() for point in points]

        print("    slots the strobe was ever high in:")
        for first, last, word in self.bands(
                [(point.tap, f"{point.ever_high():08b}")
                 for point in points]):
            print(f"      taps {first} to {last}: {word}")

        print("    run start by tap: "
              + " ".join("--" if start is None else f"{start}"
                         for start in starts))

        crossings = self.crossing(taps, starts)
        if not crossings:
            print("    the strobe's run never moves over a whole turn"
                  " of the line")
        for where, was, now in crossings:
            print(f"    the strobe's run starts {was} -> {now} slots in"
                  f" at tap {where}")

        return crossings

    @staticmethod
    def summarise_toggling(points):
        toggling = [point for point in points if point.toggling()]
        if not toggling:
            print("    the strobe never reads as a clean alternating"
                  " pattern, at any tap or in any pass")
            return

        runs = []
        for point in toggling:
            if runs and point.tap == runs[-1][-1].tap + 1:
                runs[-1].append(point)
            else:
                runs.append([point])

        for run in runs:
            print(f"    the strobe alternates over {len(run)} consecutive"
                  f" taps, {run[0].tap} to {run[-1].tap}:"
                  f" {run[0].toggling()[0]}")

    async def setup(self):
        for name in ("run", "level", "mpr", "poke", "tdqs"):
            await self.panel.control_write(name, 0)
        await Walk.take_panel(self.panel)
        await self.panel.control_write("odt", 1)
        await self.panel.control_write("snoop", 1)

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")
        self.line = Line(self.panel)
        await self.setup()

        for value in self.VALUES:
            if not await self.line.rewind():
                print("the delay lines never reported their mark:"
                      " what follows is measured from an unknown tap")
            else:
                print("every readback's delay line is at its mark")

            points = await self.sweep(value)
            home = await self.line.home()
            print(f"after {Line.TAP_COUNT} ticks the line is"
                  f" {'back at its mark' if home else 'past its mark'}")
            self.table(value, points)
            self.summarise(value, points)

        await self.panel.control_write("snoop", 0)
        await Walk.leave_panel(self.panel)
        return 0


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Walk.DEFAULT_PATH
    await Taps(path).run()
