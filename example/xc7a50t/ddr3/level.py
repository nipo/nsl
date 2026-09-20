"""Ask the part whether the strobe arrives, by write levelling.

Run with::

  acrobe run level.py [resource-path] [dqs-invert]

In write levelling the part drives its data lines with whatever it
sampled of the memory clock on each rising strobe edge.  The strobe
leaves on the clock CK leaves on, so its edges land on CK's by
construction and there is nothing to place: what is left to read is
whether the strobe reaches the part at all.

Two readings and what each means:

- the answer **leaves what the part idles at**: the part has taken the
  bus and the strobe is reaching it;
- the answer **follows nothing** and the part stays at its idle level:
  the strobe is not reaching the part, and no placement of the data
  against it can matter.

The pin is read back beside the answer, over the same pass, so a
strobe that never left the fabric is told from one the part did not
sample.

Levelling drives a strobe and nothing else, so the reading is only
worth taking with the strobe pad held over its own burst: a pad
released in the middle of one sends the part a strobe with no edges on
it, and the part answers whatever a pin nobody drove settles at.  That
is what the enable lead is for, and it comes from the board record.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from walk import Walk


class Level:
    SETTLE_SECONDS = 0.2

    def __init__(self, path, invert=0):
        self.session = Session(path)
        self.panel = None
        self.invert = invert

    async def read(self):
        # Twice: a level that is still moving reads differently each
        # time, and that is worth seeing rather than averaging away.
        first = await self.panel.status_read("level_answer")
        second = await self.panel.status_read("level_answer")
        return first, second

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        await self.panel.control_write("run", 0)
        await Walk.take_panel(self.panel, invert=self.invert)
        print(f"dq_lead {Walk.DQ_LEAD}, dqs_lead {Walk.DQS_LEAD},"
              f" dqs_invert {self.invert}")

        # Both ways round.  The specification asks for termination
        # during levelling, but with it on an undriven bus reads as
        # zero and so does a part answering zero; with it off the bus
        # holds whatever was last driven onto it, and a part that has
        # taken it over shows as every pin agreeing.
        for odt in (1, 0):
            await self.panel.control_write("odt", odt)
            print(f"--- termination {'on' if odt else 'off'}")

            await self.panel.control_write("level", 0)
            await asyncio.sleep(self.SETTLE_SECONDS)
            idle = await self.panel.status_read("level_answer")
            print(f"  not levelling:  {idle:#04x}")

            await self.panel.control_write("level", 1)
            await asyncio.sleep(1.0)

            first, second = await self.read()
            moving = "" if first == second else "  (moving)"
            spread = "" if first in (0x00, 0xff) else "  (pins disagree)"
            print(f"  levelling:      {first:#04x}{moving}{spread}")

            high = await self.panel.status_read("strobe_high")
            low = await self.panel.status_read("strobe_low")
            print(f"  strobe on the pin: ever high {high:#04x},"
                  f" ever low {low:#04x}")
            if high and low:
                print("    it toggles, so it is leaving the pin")
            else:
                print("    it never moved: the pin is not being driven")

            await self.panel.control_write("level", 0)
            await asyncio.sleep(self.SETTLE_SECONDS)

            if first == idle:
                print("  the answer never left what it idles at:"
                      " nothing says the strobe is reaching the part")
            else:
                print(f"  the answer sits at {first:#04x}: the part has taken"
                      " the bus, so the strobe reaches it")

        await Walk.leave_panel(self.panel)
        return 0


async def main():
    path, invert = Walk.parse(sys.argv[1:])
    await Level(path, invert).run()
