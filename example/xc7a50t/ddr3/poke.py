"""Write one burst, read it back, with nothing in between but the PHY.

Run with::

  acrobe run poke.py [resource-path] [dqs-invert]

The sequence goes straight at the DFI: precharge, activate, one write
burst, precharge, activate, read.  No core scheduling it, no adapter
cutting a transaction up, no walker deciding what the payload should
have been.  Whatever comes back is what this PHY put on the wire and
what the part made of it.

The burst counts up from a value the panel sets, so a burst that comes
back rotated, reversed or half-written says which rather than looking
uniformly wrong.  Changing that value and watching the answer follow
is what separates a write that landed from an array that happened to
hold something.

Three values are written in turn and the answer has to follow: one
value cannot be told from whatever the array held already, and two can.

The whole table is run twice, once either way of mode register 1 bit
A11.  That bit enables TDQS, and the datasheet says a part with TDQS
enabled supports no data mask -- which takes the one pin of the data
group nothing here can read back out of the question.  A mask pin that
never reaches the part floats at its receiver, sits at exactly VREF
with the part's own termination on it, and masks beats at random; from
outside that looks like a burst which never arrived.  If the answer
follows the value with the bit set and not without it, the mask pin is
what was hiding the burst.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from walk import Walk


class Poke:
    SETTLE_SECONDS = 0.3

    def __init__(self, path, invert=0):
        self.session = Session(path)
        self.panel = None
        self.invert = invert

    async def answer(self):
        low = await self.panel.status_read("mpr_low")
        high = await self.panel.status_read("mpr_high")
        word = (high << 32) | low
        return [(word >> (8 * i)) & 0xff for i in range(8)]

    async def once(self, value):
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("poke_value", value)
        await asyncio.sleep(0.1)
        await self.panel.control_write("poke", 1)
        await asyncio.sleep(self.SETTLE_SECONDS)
        got = await self.answer()
        count = await self.panel.status_read("mpr_count")
        await self.panel.control_write("poke", 0)
        return got, count

    async def table(self, tdqs):
        """The whole table at one setting of the TDQS bit."""
        await self.panel.control_write("poke", 0)
        await self.panel.control_write("tdqs", tdqs)
        await asyncio.sleep(0.1)

        if tdqs:
            print("\n--- TDQS enabled: the part supports no data mask")
        else:
            print("\n--- TDQS disabled: the mask pin is live")
        print("value   read back                          answers")

        follows = []
        for value in (0x10, 0x40, 0xa0):
            got, count = await self.once(value)
            want = [(value + i) & 0xff for i in range(8)]
            hits = sum(1 for a, b in zip(want, got) if a == b)
            mark = "  <- all eight" if hits == 8 else f"  {hits}/8"
            print(f" {value:#04x}   "
                  + " ".join(f"{b:02x}" for b in got)
                  + f"   {count:>3}{mark}")
            follows.append(tuple(got))

        if len(set(follows)) == 1:
            print("  the answer does not move when the value does:"
                  " the array is not taking the burst")
        else:
            print("  the answer follows the value: the burst is landing")

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        for name in ("run", "level", "mpr"):
            await self.panel.control_write(name, 0)
        # The poke's own read is the one that answers here, so the
        # capture stays where it belongs rather than on the write.
        await self.panel.control_write("snoop", 0)
        await self.panel.control_write("odt", 1)

        if self.invert == Walk.DQS_INVERT:
            # The record as the design carries it, applied by the PHY
            # itself: a table that comes back whole here says the
            # record is right, and not that a host can be made to find
            # settings that work.
            await Walk.leave_panel(self.panel)
        else:
            await Walk.take_panel(self.panel, invert=self.invert)

        for tdqs in (0, 1):
            await self.table(tdqs)

        await Walk.leave_panel(self.panel)
        return 0


async def main():
    path, invert = Walk.parse(sys.argv[1:])
    await Poke(path, invert).run()
