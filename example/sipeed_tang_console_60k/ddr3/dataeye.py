"""The read eye as the array draws it, rather than as the part's own
pattern draws it.

``mpr.py`` maps the read path against the multi purpose register, whose
answer alternates every beat.  That pattern has no two like beats in a
row, so it says where a beat is and nothing about what arbitrary data
does to the same pins.  This walks a whole region at every tap of the
line and counts the bad beats, which is the same plane read with the
traffic a design actually carries.

Run with::

  acrobe run dataeye.py [resource-path] [size=0..3] [stride=1]
                        [offset=N] [taps=first:last] [odt=0|1] [passes=N]

The region defaults to every bank at row zero, which is the smallest
one that fails, and the offset to the board record's.  ``passes``
walks the region more than once at each tap, which is how far a count
moves between two readings of the same point.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from readmap import Line
from walk import Walk


class DataEye:
    POLL_SECONDS = 0.002
    RUN_SECONDS = 20.0

    def __init__(self, path, size, stride, offset, first, last,
                 odt, passes):
        self.session = Session(path)
        self.size = size
        self.stride = stride
        self.offset = offset
        self.first = first
        self.last = last
        self.odt = odt
        self.passes = passes
        self.panel = None

    @staticmethod
    def parse(args):
        path = Walk.DEFAULT_PATH
        size = Walk.BANKS
        stride = 1
        offset = Walk.OFFSET
        first, last = 0, Line.TAP_COUNT - 1
        odt, passes = 1, 1
        for arg in args:
            key, sep, value = arg.partition("=")
            if not sep:
                path = arg
            elif key == "size":
                size = int(value, 0)
            elif key == "stride":
                stride = int(value, 0)
            elif key == "offset":
                offset = int(value, 0)
            elif key == "odt":
                odt = int(value, 0)
            elif key == "passes":
                passes = int(value, 0)
            elif key == "taps":
                head, _, tail = value.partition(":")
                first, last = int(head, 0), int(tail, 0)

        return path, size, stride, offset, first, last, odt, passes

    async def pass_errors(self):
        """One walk of the region, or None if it never said it was done."""
        await self.panel.control_write("run", 0)
        await self.panel.control_write("full", self.size)
        await self.panel.control_write("run", 1)

        waited = 0.0
        while not await self.panel.status_read("done"):
            if waited > self.RUN_SECONDS:
                await self.panel.control_write("run", 0)
                return None
            await asyncio.sleep(self.POLL_SECONDS)
            waited += self.POLL_SECONDS

        errors = await self.panel.status_read("error_count")
        first = await self.panel.status_read("first_error_address")
        await self.panel.control_write("run", 0)
        return errors, first

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        await self.panel.control_write("run", 1)
        await self.panel.control_write("run", 0)
        if not await self.panel.status_read("ready"):
            print("controller: not ready, the power-up sequence has not run")
            return 1

        for name in ("snoop", "mpr", "level", "poke"):
            await self.panel.control_write(name, 0)
        await self.panel.control_write("odt", self.odt)
        await Walk.take_panel(self.panel, offset=self.offset)

        line = Line(self.panel)
        if not await line.rewind():
            print("the delay lines never reported their mark")
            return 1

        print(f"{Walk.SIZE_NAME[self.size]} at read offset {self.offset},"
              f" termination {self.odt}, one walk a tap")
        print("  tap | bad beats | first bad address")

        best, at = None, None
        ticks = 0
        for tap in range(self.first, self.last + 1, self.stride):
            while ticks < tap:
                await line.step()
                ticks += 1

            for _ in range(self.passes):
                got = await self.pass_errors()
                if got is None:
                    print(f"  {tap:>4} | stalled")
                    continue

                errors, first = got
                where = f" {first:#x}" if errors else ""
                print(f"  {tap:>4} | {errors:>9} |{where}")
                if best is None or errors < best:
                    best, at = errors, tap

        print(f"the fewest bad beats is {best}, at tap {at}")
        await Walk.leave_panel(self.panel)
        return 0 if best == 0 else 1


async def main():
    got = DataEye.parse(sys.argv[1:])
    if await DataEye(*got).run():
        raise SystemExit(1)
