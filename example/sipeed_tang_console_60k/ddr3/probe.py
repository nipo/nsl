"""Show what the bus holds at each read offset, without judging it.

Run with::

  acrobe run probe.py [resource-path]

A sweep that finds nothing says only that nothing matched.  This says
what came back instead, which separates the three things that look
alike through a pass-or-fail line: a bus nobody is driving, a bus
driven at a moment nothing samples, and a part answering with the
wrong data because the write never landed.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from walk import Walk


class Probe:
    def __init__(self, path, taps):
        self.session = Session(path)
        self.taps = taps
        self.panel = None
        self.tick = 0

    async def delay_step(self):
        self.tick ^= 1
        await self.panel.control_write("tick", self.tick)

    async def beat(self):
        return await Walk.wide(self.panel, "first_read")

    async def one(self, offset):
        await self.panel.control_write("offset", offset)
        await self.panel.control_write("full", 0)
        await self.panel.control_write("run", 0)
        await self.panel.control_write("run", 1)
        while not await self.panel.status_read("done"):
            await asyncio.sleep(0.05)

        return (await self.panel.status_read("error_count"),
                await self.panel.status_read("read_count"),
                await self.beat())

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        # The board record on the panel, so that the slip swept below
        # moves against the rest of it and not against whatever the
        # last script left.
        await Walk.take_panel(self.panel)

        for odt in (1, 0):
            await self.panel.control_write("odt", odt)
            for slip in range(Walk.SLIP_COUNT):
                await self.panel.control_write("slip", slip)
                print(f"=== odt {odt}, data {slip} slots against the strobe")
                await self.sweep()

        await Walk.leave_panel(self.panel)
        return 0

    async def sweep(self):
        for tap in range(self.taps):
            if tap:
                await self.delay_step()
            print(f"--- delay {tap} steps in")
            seen = {}
            for offset in range(Walk.OFFSET_COUNT):
                errors, beats, word = await self.one(offset)
                seen.setdefault(word, []).append(offset)
                if errors == 0:
                    print(f"  offset {offset:2}: clean")
            for word, offsets in sorted(seen.items(),
                                        key=lambda kv: -len(kv[1])):
                span = (f"{offsets[0]}..{offsets[-1]}"
                        if len(offsets) > 1 else str(offsets[0]))
                print(f"  {word:#034x} at {len(offsets):2} offsets ({span})")


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Walk.DEFAULT_PATH
    taps = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    await Probe(path, taps).run()
