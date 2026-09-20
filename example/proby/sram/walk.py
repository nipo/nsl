"""Walk the whole SRAM through the controller and report what came back.

Run with::

  acrobe run walk.py [resource-path]

The walk writes every location of the part and reads every one of them
back, checking a payload that is a function of its own address: a
swapped or stuck address line shows up as a data mismatch rather than
quietly aliasing onto itself.
"""

import asyncio
import pathlib
import re
import sys
import time

from acrobe_plugin.gatecap.session import Session


def built_for_hz():
    """The memory rate the bitstream was built for.

    Read from the design rather than repeated here.  The rate is swept
    while the part is characterised, and a copy of it in this script
    would be one more thing to keep in step -- which is exactly the
    mistake this check exists to catch.
    """
    source = pathlib.Path(__file__).with_name("src") / "boundary.vhd"
    found = re.search(r"constant\s+ram_hz_c\s*:\s*natural\s*:=\s*(\d+)",
                      source.read_text())
    if not found:
        raise SystemExit(f"no ram_hz_c in {source}")

    return int(found.group(1))


def declared_ns():
    """The memory period the constraint generator was told about.

    Naming a clock in the CCF consumes it: the period constraint ISE
    would otherwise derive through the PLL ends up covering no path at
    all, so this number, and not the PLL ratio, is what the memory
    domain is held to.  Let it drift from the design and the build is
    checked against a clock it does not run at, quietly.
    """
    source = pathlib.Path(__file__).with_name("clocks.ccf")
    for line in source.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "ram_s":
            return float(parts[1])

    raise SystemExit(f"no ram_s clock in {source}")


class Walk:
    DEFAULT_PATH = ("proby-0/jtag-int/chain/0"
                    "/bnoc_continuous_transport/gatecap")

    TOLERANCE_PPM = 200

    # The tester stops for good when it is done, so a run is one edge
    # of the run control.
    POLL_SECONDS = 0.5

    # Walking the whole region takes a fraction of a second.  A walker
    # that stalls never raises done, so the wait needs a bound of its
    # own rather than hanging on the rack.
    TIMEOUT_SECONDS = 180

    def __init__(self, path):
        self.session = Session(path)
        self.ram_hz = built_for_hz()

        declared = declared_ns()
        wanted = 1000.0 / (self.ram_hz / 1e6)
        if abs(declared - wanted) > 0.01:
            raise SystemExit(
                f"clocks.ccf says the memory period is {declared} ns but the "
                f"design runs at {self.ram_hz} Hz, which is {wanted:.4f} ns. "
                f"The constraint generator believes the CCF, so the build was "
                f"checked against the wrong clock.")

    async def clock_ok(self):
        rates = await self.session.block_by_name("rates").rates()
        got = rates.get("ram")
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

    async def run(self):
        await self.session.open()

        if not await self.clock_ok():
            return 1

        panel = self.session.block_by_name("panel")

        if not await panel.status_read("ready"):
            print("controller: not ready, the power-up wait has not elapsed")
            return 1

        # Down then up: the tester is held in reset while run is low,
        # so this starts a walk whatever state the last one left.
        await panel.control_write("run", 0)
        await panel.control_write("run", 1)

        started = time.monotonic()
        while not await panel.status_read("done"):
            if time.monotonic() - started > self.TIMEOUT_SECONDS:
                busy = await panel.status_read("busy")
                seen = await panel.status_read("error_count")
                print(f"walk: still not done after {self.TIMEOUT_SECONDS} s, "
                      f"busy {busy}, {seen} bad beats so far")
                print("FAILED")
                return 1
            await asyncio.sleep(self.POLL_SECONDS)
        elapsed = time.monotonic() - started

        errors = await panel.status_read("error_count")
        first = await panel.status_read("first_error_address")

        # A lane's ninth bit failing to answer for the eight beside it
        # is counted in the gateware, so a marginal data line is caught
        # even between polls.
        parity = (await panel.counters_read()).get("parity_error", 0)

        # Polled, so this bounds the walk rather than measuring it.
        print(f"walk: done within {elapsed:.2f} s of the start edge")

        if errors or parity:
            if errors:
                print(f"walk: {errors} bad beats, first at byte {first:#x}")
            if parity:
                print(f"walk: {parity} beats whose parity did not answer "
                      f"for their data")
            print("FAILED")
            return 1

        print("walk: every location written and read back, parity holding")
        print("PASSED")
        return 0


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Walk.DEFAULT_PATH
    if await Walk(path).run():
        raise SystemExit(1)
