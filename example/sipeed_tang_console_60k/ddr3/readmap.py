"""The read plane, and what a point of it is worth.

Reads have two things to find and neither is in a datasheet.  The
**offset** is how many beats pass between a read being asked for and
its first beat appearing in the captured stream: the part's CAS
latency, the flight there and back, and the pipelines of both
serialisers.  The **delay** is where inside one beat the bus is
sampled, in taps of the line every data pin carries.  Together they are
a plane, and a point of it is worth what it answers rather than what it
is first to answer: a sweep that stops where a burst first comes back
whole reports one sample of a distribution, and the middle of the
window is somewhere else entirely.

``walk.py`` trains on this plane and ``eye.py`` maps it for an
operator, so the line, the table a sweep fills and the reading of its
runs are here.

The line lengthens a tap per tick and wraps past its last one, and
the mark is tap zero, so a run of n ticks from the mark leaves the
line at tap n: a tick is a tap.  Tables are by tap all the same,
because a table filled from wherever the last script left the line is
a table of ticks and says nothing.

A table may be filled at a stride, which is what makes a line of two
hundred and fifty-six taps affordable: a window tens of taps wide
cannot hide between two samples eight apart, so a coarse pass says
which offsets answer and a fine pass over those says where the middle
of the window is.  A run of a strided table is counted in samples and
its width read in taps, so the two passes report in the same units.

Runs of clean taps are counted without wrapping past the end of the
line.  This family's line is 256 taps of about 12.5 ps, which is some
two and a half beats at 400 MHz, so the plane holds about two windows
and the wrap is a jump in delay rather than a step: a run that touches
both ends is two runs here.  A run that touches either end is also one
the end of the line may have cut short, so it understates what it is
worth, and an interior run of the same width says more about where to
sit.
"""

import asyncio
import sys
import time


class Line:
    """The delay line every readback comes through, and where it sits.

    One line per data pin and one on the strobe, all stepped together
    by the panel's tick.  A tick makes the line one tap longer and the
    line wraps past its last tap, so tap n is n ticks from the mark and
    the way to a known tap is through the mark.

    A step is a change of the panel's tick and not a level, so two of
    them have to be told apart on the far side of the panel's clock
    crossing, which is what the settle is for.
    """

    TAP_COUNT = 256
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
        # One bit a data pin, and this part carries sixteen.
        return await self.panel.status_read("delay_mark") == 0xffff

    async def rewind(self):
        """Walk the line round to its mark, which is tap zero."""
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


class Table:
    """One map: a tap in every column, a read offset on every row.

    A cell carries the text it prints and the number the summaries read
    it by, which are not the same thing when a cell holds several
    passes: the text says what each pass answered, and the score is the
    worst of them, because a point is only clean if it is clean every
    time it is asked.
    """

    def __init__(self, name, title, legend, offsets, taps):
        self.name = name
        self.title = title
        self.legend = legend
        self.offsets = tuple(offsets)
        self.taps = tuple(taps)
        self.text = {}
        self.score = {}

    def put(self, offset, tap, text, score):
        self.text[(offset, tap)] = text
        self.score[(offset, tap)] = score

    def row(self, offset):
        """What the summaries read: one score a tap, in tap order."""
        return [self.score.get((offset, tap)) for tap in self.taps]

    async def fill(self, line, cell):
        """Every tap of this table's stride, and every offset at each.

        From the mark, so that a column is a position on the line and
        not a count of steps from wherever the script before this one
        left it.  The taps the table was built with say where it
        samples, and the line is walked to each of them in turn.
        """
        if not await line.rewind():
            print("  the delay lines never reported their mark: what follows"
                  " is measured from an unknown tap")

        ticks = 0
        for index, tap in enumerate(self.taps):
            while ticks < tap:
                await line.step()
                ticks += 1
            for offset in self.offsets:
                text, score = await cell(offset)
                self.put(offset, tap, text, score)
            # A whole map is minutes of the board's time, so where the
            # sweep has got to goes to the error stream: the report on
            # the output stream stays a report.
            print(f"{self.name}: tap {tap}, {index + 1} of"
                  f" {len(self.taps)}", file=sys.stderr)

    def render(self):
        width = max(len(text) for text in self.text.values())
        width = max(width, max(len(str(tap)) for tap in self.taps))
        head = " ".join(f"{tap:>{width}}" for tap in self.taps)
        print(f"--- {self.title}")
        print(f"    {self.legend}")
        print(f" offset | {head}")
        for offset in self.offsets:
            cells = " ".join(f"{self.text[(offset, tap)]:>{width}}"
                             for tap in self.taps)
            print(f"     {offset:>2} | {cells}")

    @staticmethod
    def longest(scores, limit):
        """The longest run of consecutive cells at or below a limit.

        Returns the length and the index it starts at, or zero and None
        for a row with no such cell.  A cell that never answered counts
        as a break: a pass that had to be given up on is not a reading.
        """
        best, where = 0, None
        start = None
        for index, score in enumerate(scores):
            if score is None or score > limit:
                start = None
                continue
            if start is None:
                start = index
            if index - start + 1 > best:
                best, where = index - start + 1, start

        return best, where

    @property
    def stride(self):
        """Taps between two samples of a row."""
        if len(self.taps) < 2:
            return 1

        return self.taps[1] - self.taps[0]

    def run_of(self, offset, limit):
        """A run of clean taps, as a width in taps and the taps it covers.

        The width is in taps and not in samples, so that a coarse map
        and a fine one over the same window report the same number.
        """
        length, index = self.longest(self.row(offset), limit)
        if not length:
            return 0, None, None

        first = self.taps[index]
        last = self.taps[index + length - 1]
        return last - first + self.stride, first, last

    def answering(self, limit=0):
        """Offsets with a cell at or below a limit, in offset order.

        What a coarse pass hands the fine one: an offset that never
        answered at any tap of the stride has no window to refine.
        """
        return tuple(offset for offset in self.offsets
                     if any(score is not None and score <= limit
                            for score in self.row(offset)))

    def truncated(self, first, last):
        """Whether a run runs into an end of the line.

        The line does not carry what is past its own ends, so such a
        run is as much of a window as the line can show and not as much
        as there is.
        """
        return first == self.taps[0] or last == self.taps[-1]

    def best(self):
        """The widest clean run of the whole map, as an offset and tap.

        The tap is the middle of the run, which is where a read path
        would be left: the edges of a window are where it stops
        working.  A map with no clean cell at all falls back to the
        widest run of at most one error, and the caller is told which.
        """
        for limit in (0, 1):
            found = []
            for offset in self.offsets:
                length, first, last = self.run_of(offset, limit)
                if length:
                    found.append((length, -offset, offset, first, last))
            if found:
                length, _, offset, first, last = max(found)
                return offset, (first + last) // 2, length, limit

        return None, None, 0, None

    def choose(self, limit=0):
        """Where to leave the read path, and how wide its window is.

        The widest run of the map, preferring one that ends inside the
        line: a run touching either end carries an unknown amount of
        window past that end, so an interior run of the same width is
        the better reading of the two.  Returns the offset, the middle
        tap of the run, its width, and whether the run that won still
        touches an end.
        """
        runs = []
        for offset in self.offsets:
            length, first, last = self.run_of(offset, limit)
            if length:
                runs.append((length, -offset, offset, first, last,
                             self.truncated(first, last)))

        if not runs:
            return None, None, 0, False

        widest = max(runs)
        interior = [run for run in runs if not run[5]]
        if interior and max(interior)[0] >= widest[0]:
            widest = max(interior)

        length, _, offset, first, last, touches = widest
        return offset, (first + last) // 2, length, touches

    def summarise(self):
        print(f"  {self.title}: the longest run of clean taps, and the"
              " widest run of at most one error")
        for offset in self.offsets:
            clean = self.run_of(offset, 0)
            most = self.run_of(offset, 1)
            print(f"    offset {offset}: {self.describe(clean):<28}"
                  f"  {self.describe(most)}")

    @staticmethod
    def describe(run):
        width, first, last = run
        if not width:
            return "nothing"
        if first == last:
            return f"1 sample, tap {first}"
        return f"{width} taps, taps {first} to {last}"


class Probe:
    """The short walker, asked at one point of the plane.

    Sixteen beats written and read back inside one open row: the write
    path and the read path together, which is the check a pattern the
    part holds cannot make.
    """

    # A pass of the probe walker is 256 bytes of a sixteen byte bus.
    BEATS = 16
    # Every offset the PHY's port can express.  On a board whose read
    # offset has been measured this is the place to narrow, but a
    # figure that has not been measured cannot be narrowed around.
    OFFSETS = tuple(range(128))
    # A pass of the short walker is over in microseconds.  The wait has
    # to end by itself whatever happens: a script killed in the middle
    # of a transaction wedges the transport until the part is
    # programmed again.
    TIMEOUT = 2.0
    POLL_SECONDS = 0.01

    def __init__(self, panel, size, passes=1, offsets=OFFSETS):
        self.panel = panel
        self.size = size
        self.passes = passes
        self.offsets = tuple(offsets)

    def table(self, stride=1):
        """An empty map of the plane, for this many passes a cell.

        A stride above one samples the line every that many taps, which
        is how a coarse pass is made affordable.
        """
        legend = (f"bad beats of {self.BEATS}, one pass a cell"
                  if self.passes == 1 else
                  f"bad beats of {self.BEATS}, {self.passes} passes a cell,"
                  " a/b/c")
        if stride > 1:
            legend += f", every {stride} taps"
        return Table("probe",
                     "the probe walker, the write path and the read path"
                     " together",
                     legend, self.offsets, range(0, Line.TAP_COUNT, stride))

    async def once(self, offset):
        """One pass of the short walker, or a pass given up on.

        Selected with the run down, and not the other way about: a
        walker is held in reset by the run bit and by the selection
        together, so choosing one while the run is up releases it for a
        whole host round trip before the run proper starts.
        """
        await self.panel.control_write("run", 0)
        await self.panel.control_write("full", self.size)
        await self.panel.control_write("offset", offset)
        await self.panel.control_write("run", 1)

        start = time.monotonic()
        while not await self.panel.status_read("done"):
            if time.monotonic() - start > self.TIMEOUT:
                await self.panel.control_write("run", 0)
                return None
            await asyncio.sleep(self.POLL_SECONDS)

        errors = await self.panel.status_read("error_count")
        await self.panel.control_write("run", 0)
        return errors

    async def cell(self, offset):
        """One point of the plane, as the text and the score of it."""
        passes = [await self.once(offset) for _ in range(self.passes)]
        text = "/".join("--" if errors is None else str(errors)
                        for errors in passes)
        score = None if None in passes else max(passes)
        return text, score
