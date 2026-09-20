"""Train the read path against the part's own pattern.

Run with::

  acrobe run mpr.py [resource-path]

Read training normally checks a payload the walker wrote, so it cannot
be trusted until writes work, and writes cannot be checked until reads
are trusted.  That is a circle, and the multi-purpose register is the
way out of it: in that mode every read answers with a pattern the part
holds rather than with the array, so the read offset and the delay
line can be walked against something known before a single write is
believed.

The predefined pattern is alternating bits, so one beat of it on a
byte-wide part is all ones or all zeroes and a burst of eight
alternates between them.  Which of the two comes first depends on
where the burst is caught, so both orders count as a match.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from walk import Walk

# A burst of the predefined pattern, either way up.
WANTED = (0xff00ff00ff00ff00, 0x00ff00ff00ff00ff)


class Mpr:
    SETTLE_SECONDS = 0.15

    def __init__(self, path):
        self.session = Session(path)
        self.panel = None

    async def answer(self):
        low = await self.panel.status_read("mpr_low")
        high = await self.panel.status_read("mpr_high")
        return (high << 32) | low

    async def delay_step(self, tick):
        await self.panel.control_write("tick", tick)

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        await self.panel.control_write("run", 0)
        await self.panel.control_write("level", 0)
        await self.panel.control_write("odt", 1)
        # The offset is swept below, so the PHY reads the panel's copy
        # of the board record while this runs.
        await Walk.take_panel(self.panel)
        await self.panel.control_write("mpr", 1)
        await asyncio.sleep(0.5)

        step = await self.panel.status_read("level_step")
        count = await self.panel.status_read("mpr_count")
        print(f"sequencer step {step}, {count} answers so far")
        if not count:
            print("the part is answering nothing at all: the read command"
                  " is not reaching it, or the capture never fires")
            await self.panel.control_write("mpr", 0)
            await Walk.leave_panel(self.panel)
            return 1

        tick = 0
        found = []
        seen = {}
        for tap in range(Walk.TAP_COUNT):
            for offset in range(Walk.OFFSET_COUNT):
                await self.panel.control_write("offset", offset)
                await asyncio.sleep(self.SETTLE_SECONDS)
                word = await self.answer()
                seen.setdefault(word, 0)
                seen[word] += 1
                if word in WANTED:
                    found.append((tap, offset, word))
            tick ^= 1
            await self.delay_step(tick)
            if found:
                break

        await self.panel.control_write("mpr", 0)
        await Walk.leave_panel(self.panel)

        if not found:
            print("the pattern never came back whole.  What did, most often:")
            for word, times in sorted(seen.items(), key=lambda kv: -kv[1])[:6]:
                print(f"  {word:#018x}  at {times} points")
            return 1

        for tap, offset, word in found:
            print(f"pattern at offset {offset}, {tap} delay steps in:"
                  f" {word:#018x}")
        print("the read path is trained against something the part made,"
              " and owes nothing to a write")
        return 0


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Walk.DEFAULT_PATH
    if await Mpr(path).run():
        raise SystemExit(1)
