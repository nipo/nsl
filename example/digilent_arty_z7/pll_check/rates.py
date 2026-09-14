"""Read every rate the board generates and compare it to the plan.

Run with::

  acrobe run rates.py [resource-path]

The expected rates are the ones the elaboration-time solver committed
to, so a mismatch is either a divider the backend got wrong or a
clock that is not running at all.
"""

import sys

from acrobe_plugin.gatecap.session import Session


class RateCheck:
    DEFAULT_PATH = ("dig-003017a4c9e1/jtag/chain/0"
                    "/bnoc_continuous_transport/gatecap")

    # MMCM: reference over five, VCO 900 MHz, then these dividers.
    # PLL: reference over five, VCO 1050 MHz.
    EXPECTED = {
        "p0": 12_000_000,
        "p90": 12_000_000,
        "p180": 12_000_000,
        "p270": 12_000_000,
        "rack": 100_000_000,
        "sample": 87_500_000,
        "f150m": 150_000_000,
        "f50m": 50_000_000,
        "f25m": 25_000_000,
        "f10m": 10_000_000,
    }

    # The measurer counts edges over one second of its reference, so a
    # rate is exact to a hertz; the crystal's own error is what is
    # left, and that is parts per million.
    TOLERANCE_PPM = 200

    def __init__(self, path):
        self.session = Session(path)

    async def run(self):
        await self.session.open()
        rates = await self.session.block_by_name("rates").rates()

        bad = 0
        for name, want in self.EXPECTED.items():
            got = rates.get(name)
            if got is None:
                print(f"{name:>8}: absent from the rack")
                bad += 1
                continue
            ppm = (got - want) / want * 1e6
            ok = abs(ppm) <= self.TOLERANCE_PPM
            print(f"{name:>8}: {got:>11} Hz  want {want:>11} Hz"
                  f"  {ppm:+8.1f} ppm  {'ok' if ok else 'BAD'}")
            if not ok:
                bad += 1

        extra = set(rates) - set(self.EXPECTED)
        for name in sorted(extra):
            print(f"{name:>8}: {rates[name]:>11} Hz  not in the plan")

        print("FAILED" if bad else "PASSED")
        return bad


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else RateCheck.DEFAULT_PATH
    if await RateCheck(path).run():
        raise SystemExit(1)
