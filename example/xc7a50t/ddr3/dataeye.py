"""The read window as the array draws it, rather than as the part's own
pattern draws it.

``mpr.py``, and the third map of ``eye.py``, walk the read path against
the multi purpose register, whose answer alternates every beat.  That
is the most benign pattern a bus can carry: no two like beats in a row,
so nothing of one beat is left on the pins for the next one to fight.
It says where a beat is, and nothing about what arbitrary data does to
the same pins, so the window it draws is wider than the window real
traffic has -- and the middle of the wide one need not be the middle of
the narrow one.  Training on it is necessary and not sufficient: it is
the only reference there is before a write works, and the array is the
better one the moment a write does.

This walks a region of the array at every tap of the line, at one read
offset, and counts the bad beats of each.  The same plane, read with
the payload a design actually carries.

Run with::

  acrobe run dataeye.py [resource-path] [size=0..3] [offset=N]
                        [passes=N]

The region defaults to the whole part, which is a second of the board's
time a tap.  ``passes`` walks it more than once a tap, and a tap then
counts as clean only if every pass of it was.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session

from readmap import Line, Probe, Table
from walk import Walk


class DataEye:
    # A walk of the whole part is over in a second; a tap the part
    # cannot be read at does not make it longer, so anything past this
    # is a pass that will not end.
    TIMEOUT = 20.0

    def __init__(self, path, size, offset, passes):
        self.session = Session(path)
        self.size = size
        self.offset = offset
        self.passes = passes
        self.panel = None

    @staticmethod
    def parse(args):
        path = Walk.DEFAULT_PATH
        size, offset, passes = Walk.WHOLE, Walk.OFFSET, 1
        for arg in args:
            key, sep, value = arg.partition("=")
            if not sep:
                path = arg
            elif key == "size":
                size = int(value, 0)
            elif key == "offset":
                offset = int(value, 0)
            elif key == "passes":
                passes = int(value, 0)

        return path, size, offset, passes

    async def run(self):
        await self.session.open()
        self.panel = self.session.block_by_name("panel")

        if not await self.panel.status_read("ready"):
            print("controller: not ready, the power-up sequence has not run")
            return 1

        for name in ("run", "level", "mpr", "poke", "tdqs", "snoop"):
            await self.panel.control_write(name, 0)
        await self.panel.control_write("odt", 1)
        # The tap is swept below, so the PHY reads the panel's copy of
        # the board record while this runs.
        await Walk.take_panel(self.panel, offset=self.offset)

        probe = Probe(self.panel, self.size, self.passes, (self.offset,),
                      self.TIMEOUT)
        legend = (f"bad beats of a walk of {Walk.SIZE_NAME[self.size]},"
                  f" {self.passes} walks a tap"
                  if self.passes > 1 else
                  f"bad beats of a walk of {Walk.SIZE_NAME[self.size]},"
                  " one walk a tap")
        table = Table("array",
                      "the walker on the array, the window real data has",
                      legend, (self.offset,), range(Line.TAP_COUNT))
        await table.fill(Line(self.panel), probe.cell)
        table.render()
        print()
        table.summarise()

        length, first, last = table.run_of(self.offset, 0)
        if length:
            print(f"the array is read whole over {length} taps, taps {first}"
                  f" to {last}, whose middle is tap {(first + last) // 2}")
            if table.truncated(first, last):
                print("  that run reaches an end of the line, where the line"
                      " stops rather than the window: its middle is as much"
                      " as this can see")
        else:
            print("no tap of the line reads the array whole at this offset")

        await self.panel.control_write("run", 0)
        await Walk.leave_panel(self.panel)
        return 0 if length else 1


async def main():
    got = DataEye.parse(sys.argv[1:])
    if await DataEye(*got).run():
        raise SystemExit(1)
