"""Train the read path against the part's own pattern.

Run with::

  acrobe run mpr.py [resource-path] [stride=N]

Read training normally checks a payload the walker wrote, so it cannot
be trusted until writes work, and writes cannot be checked until reads
are trusted.  That is a circle, and the multi-purpose register is the
way out of it: in that mode every read answers with a pattern the part
holds rather than with the array, so the read offset and the delay
line can be walked against something known before a single write is
believed.

This is therefore the first thing on a new board that says whether the
read path works at all.  It touches no write and no walker: a map that
comes back empty here is a command that is not reaching the part, a
part that is not answering, or a capture that never fires, and nothing
about the write path.

The predefined pattern is alternating bits, so one beat of it on a
sixteen bit part is all ones or all zeroes on both bytes and a burst of
eight alternates between them.  Which of the two comes first depends on
where the burst is caught, so both orders count as a match.

The plane is the same one ``readmap.py`` describes -- every read offset
the PHY's port can express, at taps of the delay line -- and it is
mapped in two passes for the same reason ``walk.py`` trains in two:
this family's line is 256 taps long, and a window tens of taps wide
cannot hide between two samples eight apart.  ``stride=N`` sets the
coarse step; ``stride=1`` maps the whole plane a tap at a time and
takes hours.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from readmap import Line, Table
from walk import Walk

# A burst of the predefined pattern, either way up.  A cycle is laid
# out a byte lane at a time inside a slot, so a slot of all ones is two
# bytes of it.
WANTED = (0x0000ffff0000ffff0000ffff0000ffff,
          0xffff0000ffff0000ffff0000ffff0000)


class Answer:
    """One point of the plane: whether the part's own pattern came back.

    A cell carries the mark the table prints and the score the
    summaries read it by, and the words it saw go into a tally beside
    it: a map with no match anywhere is worth nothing without what came
    back instead.
    """

    SETTLE_SECONDS = 0.15

    def __init__(self, panel):
        self.panel = panel
        self.seen = {}

    async def cell(self, offset):
        await self.panel.control_write("offset", offset)
        await asyncio.sleep(self.SETTLE_SECONDS)
        word = await Walk.wide(self.panel, "mpr")
        self.seen.setdefault(word, 0)
        self.seen[word] += 1
        if word in WANTED:
            return "ok", 0

        return "--", 1

    def table(self, offsets, stride):
        legend = "the part's own pattern, whole or not"
        if stride > 1:
            legend += f", every {stride} taps"
        return Table("mpr",
                     "the multi purpose register, the read path alone",
                     legend, offsets, range(0, Line.TAP_COUNT, stride))

    def report_silence(self):
        print("the pattern never came back whole.  What did, most often:")
        for word, times in sorted(self.seen.items(),
                                  key=lambda kv: -kv[1])[:6]:
            print(f"  {word:#034x}  at {times} points")
        if set(self.seen) <= {0, (1 << 128) - 1}:
            print("  a cycle of all ones or all zeroes is a bus nobody drove:"
                  " look at the command pins before the capture")


class Mpr:
    def __init__(self, path, stride=Walk.COARSE_STRIDE):
        self.session = Session(path)
        self.stride = stride
        self.panel = None
        self.line = None

    async def enter(self):
        """Put the part in register mode, and say whether it answers.

        Nothing below is worth mapping if no answer ever arrives: the
        count of answers separates a read command that is not reaching
        the part from one whose answer is landing somewhere the capture
        is not looking.
        """
        await self.panel.control_write("run", 0)
        await self.panel.control_write("level", 0)
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("snoop", 0)
        await self.panel.control_write("odt", 1)
        # The offset is swept below, so the PHY reads the panel's copy
        # of the board record while this runs.
        await Walk.take_panel(self.panel)
        await self.panel.control_write("mpr", 1)
        await asyncio.sleep(0.5)

        step = await self.panel.status_read("level_step")
        count = await self.panel.status_read("mpr_count")
        print(f"sequencer step {step}, {count} answers so far")
        return count

    async def leave(self):
        await self.panel.control_write("mpr", 0)
        await Walk.leave_panel(self.panel)

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")
        self.line = Line(self.panel)

        if not await self.enter():
            print("the part is answering nothing at all: the read command"
                  " is not reaching it, or the capture never fires")
            await self.leave()
            return 1

        answer = Answer(self.panel)
        offsets = tuple(range(Walk.OFFSET_COUNT))
        coarse = answer.table(offsets, self.stride)
        await coarse.fill(self.line, answer.cell)
        coarse.summarise()

        offsets = coarse.answering()
        if not offsets:
            answer.report_silence()
            await self.leave()
            return 1

        print(f"offsets that answered coarsely: {offsets}")
        if self.stride > 1:
            fine = answer.table(offsets, 1)
            await fine.fill(self.line, answer.cell)
            fine.summarise()
        else:
            fine = coarse

        offset, tap, width, touches = fine.choose()
        if offset is None:
            print("the coarse pass answered and the fine one did not:"
                  " the read path is not repeatable where it was found")
            answer.report_silence()
            await self.leave()
            return 1

        if touches:
            print("  every clean run reaches an end of the delay line, where"
                  " the line stops rather than the window: the widest of them"
                  " is as much as this can see")
        print(f"the part's pattern comes back at read offset {offset},"
              f" over {width} taps of the line; the middle of that run is"
              f" tap {tap}")
        if width < Walk.EYE_MINIMUM:
            print(f"  {width} taps is an edge and not a window; the read path"
                  " is marginal wherever it is left")
        print(f"board_c wants read_offset => {offset}, read_tap => {tap}")
        print("the read path is trained against something the part made,"
              " and owes nothing to a write")

        await self.leave()
        return 0


async def main():
    path, _ = Walk.parse(sys.argv[1:])
    stride = Walk.option(sys.argv[1:], "stride", Walk.COARSE_STRIDE)
    if await Mpr(path, stride).run():
        raise SystemExit(1)
