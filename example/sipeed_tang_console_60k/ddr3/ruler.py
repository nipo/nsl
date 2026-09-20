"""Time the write burst against its own command, with the read path as the ruler.

Run with::

  acrobe run ruler.py [resource-path] [dqs-invert]

The data pads are buffers, so this design's own receivers see what it
drives.  Nothing stops a capture being announced on the cycle of a
*write*: what the read offset then finds is our own burst, and the
offset it turns up at counts the slots from the write command to the
data, in the same units the read offset is trained in.

That is a measurement nothing else here makes.  The write command is
decoded, the strobe reaches the part and the data is on the pin, each
established on its own -- and none of those says the data and the
strobe are at the pin at the same moment.  The strobe is read back on
the pin it leaves by, through the same delay line and the same capture
as the data, and picked out of that capture with the same offset, so
the two words printed side by side are the same eight slots.

What to expect, from the read reference alone: at DDR3-800 the part's
CAS latency is six and its CAS write latency is five, so a burst seen
in loopback with no flight either way belongs two slots ahead of
wherever the part's own pattern comes back -- ``R - 2*6 + 2*5``, give
or take a slot, for the offset ``R`` that ``mpr.py`` found.  A whole
cycle away from that -- eight slots -- is a finding rather than a
rounding.

The strobe is read back a lane at a time, and the two lanes have their
own pairs and their own routing: lanes that disagree by a slot are a
reading, and lanes that disagree by more are a lane whose pair is not
being driven.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from walk import Walk

# The two orders a toggling strobe reads as, one bit a slot.
TOGGLING = ("01010101", "10101010")


class Ruler:
    SETTLE_SECONDS = 0.05
    VALUES = (0x10, 0x40)

    def __init__(self, path, invert=0):
        self.session = Session(path)
        self.panel = None
        self.invert = invert

    async def answer(self):
        """The captured cycle, earliest byte first, and each lane's strobe."""
        got = Walk.burst_bytes(await Walk.wide(self.panel, "mpr"))
        return got, await Walk.strobes(self.panel, "strobe_word")

    async def rewind_delay(self):
        """Walk every data pin's delay line back to its shortest tap.

        The line only lengthens and wraps, and an earlier script may
        have left it anywhere, so the way to a known tap is round.
        """
        tick = 0
        for _ in range(2 * Walk.TAP_COUNT):
            mark = await self.panel.status_read("delay_mark")
            if mark == 0xffff:
                return True
            tick ^= 1
            await self.panel.control_write("tick", tick)
            await asyncio.sleep(0.02)

        return False

    @staticmethod
    def shape(got, value):
        """How the captured word stands against the burst that was sent."""
        want = [(value + i) & 0xff for i in range(Walk.BEAT_BYTES)]
        if got == want:
            return "in order"

        for k in range(1, Walk.BEAT_BYTES):
            if got == want[k:] + want[:k]:
                return f"rotated by {k}"

        back = want[::-1]
        if got == back:
            return "reversed"

        for k in range(1, Walk.BEAT_BYTES):
            if got == back[k:] + back[:k]:
                return f"reversed and rotated by {k}"

        return None

    async def sweep(self, value):
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("poke_value", value)
        await asyncio.sleep(0.05)
        await self.panel.control_write("poke", 1)
        await asyncio.sleep(0.2)

        rows = []
        for offset in range(Walk.OFFSET_COUNT):
            await self.panel.control_write("offset", offset)
            await asyncio.sleep(self.SETTLE_SECONDS)
            got, strobe = await self.answer()
            rows.append((got, strobe))

        await self.panel.control_write("poke", 0)
        return rows

    def report(self, value, rows):
        print(f"--- poke value {value:#04x},"
              " capture announced on the write")
        print("offset  data, earliest byte first"
              + " " * (3 * Walk.BEAT_BYTES - 25) + "   strobe by lane")
        for offset, (got, strobe) in enumerate(rows):
            print(f"  {offset:>4}  " + " ".join(f"{b:02x}" for b in got)
                  + f"   {Walk.strobe_text(strobe)}")

        found = [(offset, self.shape(got, value))
                 for offset, (got, _) in enumerate(rows)
                 if self.shape(got, value) is not None]

        print()
        if not found:
            print(f"  value {value:#04x}: the burst is at no offset at all,"
                  " in any order")
        for offset, how in found:
            print(f"  value {value:#04x}: the burst is at offset {offset},"
                  f" {how}")
            for near in (offset - 1, offset, offset + 1):
                if 0 <= near < len(rows):
                    mark = " <-" if near == offset else "   "
                    print(f"    strobe at offset {near}:"
                          f" {Walk.strobe_text(rows[near][1])}{mark}")

        for lane in range(Walk.LANES):
            toggling = [offset for offset, (_, strobe) in enumerate(rows)
                        if f"{strobe[lane]:08b}" in TOGGLING]
            if not toggling:
                print(f"  strobe {lane} toggles at no offset: over the slots"
                      " this capture covers it never moves")
                continue
            print(f"  strobe {lane} toggles at these offsets, and the data"
                  " beside it:")
            for offset in toggling:
                got, strobe = rows[offset]
                print(f"    offset {offset:>4}:  "
                      + " ".join(f"{b:02x}" for b in got)
                      + f"   {Walk.strobe_text(strobe)}")
        print()

        return found

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        for name in ("run", "level", "mpr", "poke", "tdqs"):
            await self.panel.control_write(name, 0)
        # The board record on the panel: the offset is swept below, so
        # the four the sweep does not touch have to be somewhere known.
        # The leads above all, because a run read here has to be the
        # burst and not a pad the schedule let go of in the middle of
        # it.
        await Walk.take_panel(self.panel, invert=self.invert)
        await self.panel.control_write("odt", 1)
        await self.panel.control_write("snoop", 1)

        print(f"dq_lead {Walk.DQ_LEAD}, dqs_lead {Walk.DQS_LEAD},"
              f" dqs_invert {self.invert}")

        if not await self.rewind_delay():
            print("the delay lines never reported their shortest tap:"
                  " what follows is measured from an unknown one")
        else:
            print("every data pin's delay line is at its shortest tap")

        summary = []
        for value in self.VALUES:
            rows = await self.sweep(value)
            summary.append((value, self.report(value, rows)))

        await self.panel.control_write("snoop", 0)
        await Walk.leave_panel(self.panel)

        print("summary")
        for value, found in summary:
            if not found:
                print(f"  {value:#04x}: nowhere")
            else:
                print(f"  {value:#04x}: "
                      + ", ".join(f"offset {offset} {how}"
                                  for offset, how in found))
        return 0


async def main():
    path, invert = Walk.parse(sys.argv[1:])
    await Ruler(path, invert).run()
