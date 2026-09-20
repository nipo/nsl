"""Walk the whole SDRAM through the controller and report what came back.

Run with::

  acrobe run walk.py [resource-path] [count]

The walk writes every location of the part and reads every one back,
checking a payload that is a function of its own address: a swapped or
stuck address line shows up as a data mismatch rather than quietly
aliasing onto itself.

A bare number is how many walks to run, one after another out of one
session, and anything else is the resource path.  Every walk is run
from the same session on purpose: a script killed inside a transfer
keeps the FTDI interface, and the next process waits on it forever
without printing a line, which reads exactly like a dead design.

What the bus did while each walk ran is printed with it.  An error
count says a walk went wrong and nothing about where; the channel
counters say which transfer a stalled walk is waiting on, and the
command counters say whether the controller is still asking the part
for anything at all.
"""

import asyncio
import pathlib
import re
import sys
import time

from acrobe_plugin.gatecap.session import Session


def built_for_hz():
    """The memory rate the bitstream was built for.

    Read from the design rather than repeated here, so the two cannot
    drift while the rate is being swept.
    """
    source = pathlib.Path(__file__).with_name("src") / "boundary.vhd"
    found = re.search(r"constant\s+ram_hz_c\s*:\s*natural\s*:=\s*(\d+)",
                      source.read_text())
    if not found:
        raise SystemExit(f"no ram_hz_c in {source}")

    return int(found.group(1))


def built_for_capture():
    """The capture cycle the bitstream was built for.

    One line of the design says it and one build carries one value, so
    a swept figure is named in the output rather than remembered.
    """
    source = pathlib.Path(__file__).with_name("src") / "boundary.vhd"
    found = re.search(r"constant\s+capture_ck_c\s*:\s*natural\s*:=\s*(\d+)",
                      source.read_text())
    if not found:
        raise SystemExit(f"no capture_ck_c in {source}")

    return int(found.group(1))


class Walk:
    DEFAULT_PATH = ("ftdi-dk0gfmir/icepizero/jtag/chain/0"
                    "/bnoc_continuous_transport/gatecap")

    # What the panel counts on the bus the walker drives, and what the
    # controller put on the command pins.  Printed in this order, so a
    # stall reads as the place the movement stops.
    AXI_COUNTERS = (("aw", "aw_count"), ("w", "w_count"), ("b", "b_count"),
                    ("ar", "ar_count"), ("r", "read_count"))
    CMD_COUNTERS = (("act", "act_count"), ("pre", "pre_count"),
                    ("wr", "wr_count"), ("rd", "rd_count"),
                    ("ref", "ref_count"), ("mrs", "mrs_count"))

    # Both sides of every channel, in the order the panel packs them.
    CHANNELS = ("aw", "w", "b", "ar", "r")

    TOLERANCE_PPM = 200
    # The walk runs by itself once the run bit is up and the host only
    # asks whether it is over, so how often it asks is the resolution
    # of the time it reports.
    POLL_SECONDS = 0.02
    # A whole-part walk at these rates is over in a second or so, and a
    # walk that is not over in this long is one that will never end.
    # The wait has to end by itself: a script killed in the middle of a
    # transaction wedges the transport until the part is programmed
    # again.
    TIMEOUT_SECONDS = 30.0
    REPORT_SECONDS = 1.0
    # The part's power-up sequence is about a hundred microseconds and
    # the host cannot ask that fast; anything past this is a
    # controller that is not sequencing at all.
    READY_SECONDS = 5.0

    def __init__(self, path, count=1):
        self.session = Session(path)
        self.count = count
        self.ram_hz = built_for_hz()
        self.capture_ck = built_for_capture()
        self.panel = None

    async def clock_ok(self):
        # The measurer counts over a second of its reference, so a
        # reading taken straight after the part is configured is a
        # part-counted one.  Give it a few refreshes before believing
        # it says the clock is wrong.
        got = None
        for _ in range(5):
            rates = await self.session.block_by_name("rates").rates()
            got = rates.get("ram")
            if got is not None and abs(got - self.ram_hz) <= (
                    self.ram_hz * self.TOLERANCE_PPM / 1e6):
                break
            await asyncio.sleep(1.0)

        if got is None:
            print("ram: absent from the rack")
            return False

        ppm = (got - self.ram_hz) / self.ram_hz * 1e6
        ok = abs(ppm) <= self.TOLERANCE_PPM
        print(f"ram clock: {got:>11} Hz  want {self.ram_hz:>11} Hz"
              f"  {ppm:+8.1f} ppm  {'ok' if ok else 'BAD'}")
        if not ok:
            print("  a memory clock that is not the one the controller was "
                  "built for makes every timing below meaningless")
        return ok

    async def counters(self):
        """Every counter the panel carries, in one reading."""
        got = {}
        for _, name in self.AXI_COUNTERS + self.CMD_COUNTERS:
            got[name] = await self.panel.status_read(name)
        for name in ("last_aw", "last_ar", "handshake"):
            got[name] = await self.panel.status_read(name)

        return got

    @classmethod
    def handshake_line(cls, word):
        """Which side of which channel is waiting, right now.

        A channel reads ``-`` for a side that is not asserted, so a
        stalled bus shows one letter standing alone: the side that is
        offering, against a side that never answers.
        """
        out = []
        for index, name in enumerate(cls.CHANNELS):
            valid = (word >> (2 * index)) & 1
            ready = (word >> (2 * index + 1)) & 1
            out.append(f"{name}{'V' if valid else '-'}{'R' if ready else '-'}")

        return " ".join(out)

    @classmethod
    def counter_line(cls, seconds, ready, busy, done, got):
        axi = " ".join(f"{tag} {got[name]}" for tag, name in cls.AXI_COUNTERS)
        cmd = " ".join(f"{tag} {got[name]}" for tag, name in cls.CMD_COUNTERS)
        return (f"{seconds:5.1f}s  ready {ready} busy {busy} done {done}"
                f"  | {axi}"
                f"  | last aw {got['last_aw']:#x} ar {got['last_ar']:#x}"
                f"  | {cmd}"
                f"  | {cls.handshake_line(got['handshake'])}")

    async def report(self, seconds, got=None):
        """One line of where the run has got to."""
        ready = await self.panel.status_read("ready")
        busy = await self.panel.status_read("busy")
        done = await self.panel.status_read("done")
        if got is None:
            got = await self.counters()
        print(self.counter_line(seconds, ready, busy, done, got))

    async def at_rest(self):
        """What the panel says with the walker held in reset.

        Nothing is driving the bus here and nothing has been counted,
        so every figure below is zero on a design whose walker the
        reset really reaches.  A count that is not zero, or one that
        moves between the two readings, is a walker running while it
        is held reset, and every walk after it is a reading of that
        rather than of the part.

        The controller shares that reset, so it reads not ready here
        and its own command counters stand still: the part is not
        being refreshed either, which is why the run is raised again
        rather than left down.

        The run is raised before it is dropped, and that is not
        redundant.  A control register comes out of configuration
        reading one here rather than zero, and writing the value the
        host already believes is there does not reach the fabric: the
        first walk of a session then starts a walker that has been
        running since the clock did, from whatever state
        configuration left it in.  One raise makes the drop a
        transition, and a transition is what resets anything.
        """
        await self.panel.control_write("run", 1)
        await self.panel.control_write("run", 0)
        print("--- at rest, walker held in reset")
        await self.report(0.0)
        await asyncio.sleep(1.0)
        await self.report(1.0)
        errors = await self.panel.status_read("error_count")
        if errors:
            print(f"at rest: error_count {errors}, which is a walker that"
                  " the reset does not reach")
            return False

        return True

    async def walk(self, index):
        """One measured pass, with what the bus did while it ran."""
        print(f"--- walk {index}")
        # Down then up: the walker is held in reset while the run is
        # low, so this starts a walk whatever the last one left behind,
        # and the counters start from zero with it.
        await self.panel.control_write("run", 0)
        await self.panel.control_write("run", 1)

        # The controller leaves reset with the walker, so the part's
        # power-up sequence runs at the front of every walk.  Nothing
        # the walker offers is taken until that is over.
        start = time.monotonic()
        while not await self.panel.status_read("ready"):
            if time.monotonic() - start > self.READY_SECONDS:
                print(f"walk {index}: the controller did not come ready in"
                      f" {self.READY_SECONDS:.0f} s, so the power-up sequence"
                      " has not run")
                await self.report(time.monotonic() - start)
                return 1
            await asyncio.sleep(self.POLL_SECONDS)

        start = time.monotonic()
        due = 0.0
        stalled = False
        while not await self.panel.status_read("done"):
            now = time.monotonic() - start
            if now >= due:
                await self.report(now)
                due = now + self.REPORT_SECONDS
            if now > self.TIMEOUT_SECONDS:
                stalled = True
                break
            await asyncio.sleep(self.POLL_SECONDS)

        elapsed = time.monotonic() - start
        got = await self.counters()
        await self.report(elapsed, got)

        if stalled:
            print(f"walk {index}: still busy after"
                  f" {self.TIMEOUT_SECONDS:.0f} s; the line above is where it"
                  " stopped")
            await self.report_silence()
            print(f"walk {index}: STALLED")
            return 1

        errors = await self.panel.status_read("error_count")
        first = await self.panel.status_read("first_error_address")

        if errors:
            print(f"walk {index}: {errors} bad beats, first at byte"
                  f" {first:#x}")
            await self.report_silence()
            print(f"walk {index}: FAILED")
            return 1

        self.throughput(elapsed, got)
        print(f"walk {index}: every location written and read back, PASSED")
        return 0

    def throughput(self, elapsed, got):
        """What the walk cost, in time and in controller cycles."""
        cycles = elapsed * self.ram_hz
        print(f"walk: {elapsed:.2f} s to done,"
              f" about {cycles / 1e6:.1f}M controller cycles")
        if got["aw_count"]:
            print(f"  {cycles / got['aw_count']:.1f} cycles a transaction,"
                  f" written and read back,"
                  f" over {got['aw_count']} of them")

    async def report_silence(self):
        """The first word the part handed back, for a walk that failed.

        A part that is not driving the bus at all and one driving it at
        the wrong moment read the same through an error count, and
        differently here.
        """
        first = await self.panel.status_read("first_read")
        beats = await self.panel.status_read("read_count")
        print(f"  beats returned: {beats}")
        print(f"  first beat read: {first:#06x}")
        if first in (0, 0xffff):
            print("  a beat of all ones or all zeroes is a bus nobody drove:"
                  " look at the command pins before the capture")
        elif beats:
            print("  the part is driving; what is wrong is when it is"
                  f" sampled, which capture_ck_c {self.capture_ck} places")

    async def run(self):
        await self.session.open()

        if not await self.clock_ok():
            return 1

        self.panel = self.session.block_by_name("panel")

        print(f"built for {self.ram_hz} Hz, capture_ck_c {self.capture_ck}")

        rest_ok = await self.at_rest()

        bad = 0
        for index in range(1, self.count + 1):
            bad += await self.walk(index)

        print(f"--- {self.count - bad} of {self.count} walks clean")
        return 0 if rest_ok and not bad else 1


def parse(args):
    """The resource path and the walk count, in either order.

    A bare number is the count and anything else is the path, so
    neither has to be spelled out to give the other.
    """
    path = Walk.DEFAULT_PATH
    count = 1
    for arg in args:
        if arg.isdigit():
            count = int(arg)
        else:
            path = arg

    return path, count


async def main():
    path, count = parse(sys.argv[1:])
    if await Walk(path, count).run():
        raise SystemExit(1)
