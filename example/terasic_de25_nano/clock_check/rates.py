"""Read the PLL, internal oscillator and DDR output rates off the board.

Run with::

  acrobe run rates.py [resource-path]

Four rates are read against the 50 MHz oscillator the transport and
the measurer ride:

``pll0``, ``pll1``
  the PLL's two outputs as the fabric sees them, asked for at 100 and
  125 MHz.

``internal``
  the SDM's internal oscillator, whose rate the data sheet does not
  state.

``loopback``
  ``pll0`` after a DDR output block, a header pin and that pin's own
  input buffer.  It is a square wave at the whole clock rate: a
  reading that matches ``pll0`` is both halves of the period reaching
  the pad.

The loopback is then stopped from the panel and read again.  A rate
that does not fall with it is a measurer counting some other net, and
the reading above proves nothing.
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session


class Rates:
    DEFAULT_PATH = "ub3-/jtag/chain/0/sld/continuous_transport/gatecap"

    EXPECTED_HZ = {"pll0": 100_000_000, "pll1": 125_000_000,
                   "loopback": 100_000_000}

    # The measurer counts over a second of its reference, so a reading
    # taken straight after a change is a part-counted one.
    SETTLE_SECONDS = 2.5
    TOLERANCE_PPM = 200

    def __init__(self, path):
        self.path = path
        self.session = Session(path)

    async def settled_rates(self):
        await asyncio.sleep(self.SETTLE_SECONDS)
        return await self.session.block_by_name("rates").rates()

    def report(self, name, got, want):
        error_ppm = abs(got - want) * 1e6 / want
        verdict = "ok" if error_ppm <= self.TOLERANCE_PPM else "OFF"
        print(f"  {name:9} {got:>11} Hz, asked {want:>11} Hz  {verdict}")
        return verdict == "ok"

    async def run(self):
        fingerprint = await self.session.open()
        print(f"rack fingerprint {fingerprint:#010x}")
        panel = self.session.block_by_name("panel")
        good = True

        await panel.control_write("still", 0)
        print(f"locked {await panel.status_read('locked')}")

        rates = await self.settled_rates()
        print("running:")
        for name, want in self.EXPECTED_HZ.items():
            good &= self.report(name, rates[name], want)
        print(f"  internal  {rates['internal']:>11} Hz")

        await panel.control_write("still", 1)
        rates = await self.settled_rates()
        stopped = rates["loopback"] == 0
        print("still:")
        print(f"  loopback  {rates['loopback']:>11} Hz"
              f"  {'ok' if stopped else 'STILL MOVING'}")
        good &= stopped

        await panel.control_write("still", 0)
        await self.session.close()
        return 0 if good else 1


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Rates.DEFAULT_PATH
    return await Rates(path).run()
