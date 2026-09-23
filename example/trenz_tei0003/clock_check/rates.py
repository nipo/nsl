"""Read the PLL rate and the DDR output's rate off the board.

Run with::

  acrobe run rates.py [resource-path]

Two rates are read against the 12 MHz oscillator the transport rides:

``fabric``
  the PLL output as the fabric sees it.

``loopback``
  the same clock after a DDR output block, a header pin and that pin's
  own input buffer.  It is a square wave at the whole clock rate,
  which an output register clocked by that clock cannot reach: a
  reading that matches ``fabric`` is both halves of the period
  reaching the pad.

The loopback is then stopped from the panel and read again.  A rate
that does not fall with it is a measurer counting some other net, and
the reading above proves nothing.
"""

import asyncio
import pathlib
import re
import sys

from acrobe.adapter.model import get_hw_root
from acrobe.protocol.serial import SerialConfig

from acrobe_plugin.gatecap.session import Session


class Rates:
    DEFAULT_PATH = ("tty-usb-Arrow_Arrow_USB_Blaster_TEI0003_ARA41546-if01-port0"
                    "/serial/hdlc/addr00/gatecap")

    BAUD_C = 1000000

    # The measurer counts over a second of its reference, so a reading
    # taken straight after a change is a part-counted one.  This is how
    # many refreshes to allow before a rate is believed.
    SETTLE_SECONDS = 2.5
    TOLERANCE_PPM = 200

    def __init__(self, path):
        self.path = path
        self.session = Session(path)
        self.expected_hz = self.built_for_hz()

    @staticmethod
    def built_for_hz():
        """The rate the bitstream asked the PLL for.

        Read from the design rather than repeated here, so the two
        cannot drift while the rate is being swept.
        """
        source = pathlib.Path(__file__).with_name("src") / "boundary.vhd"
        found = re.search(r"constant\s+fabric_hz_c\s*:\s*natural\s*:=\s*(\d+)",
                          source.read_text())
        if not found:
            raise SystemExit(f"no fabric_hz_c in {source}")

        return int(found.group(1))

    async def line_up(self):
        """Put the tty at the gateware's rate, and in raw mode with it."""
        adapter, port = self.path.strip("/").split("/")[:2]
        hw_root = get_hw_root()
        await hw_root.ensure_started()
        node = await hw_root.child_summon(adapter, port)
        applied = await node.config_set(SerialConfig(baud=self.BAUD_C))
        print(f"port {adapter}/{port} at {applied}")

    async def settled_rates(self):
        await asyncio.sleep(self.SETTLE_SECONDS)
        return await self.session.block_by_name("rates").rates()

    def report(self, name, got, want):
        ppm = (got - want) / want * 1e6 if want else 0.0
        ok = want and abs(ppm) <= self.TOLERANCE_PPM
        print(f"{name:>9}: {got:>11} Hz  want {want:>11} Hz"
              f"  {ppm:+8.1f} ppm  {'ok' if ok else 'BAD'}")
        return bool(ok)

    async def run(self):
        await self.line_up()
        print(f"rack fingerprint {await self.session.open():#010x}")

        panel = self.session.block_by_name("panel")
        print(f"locked {await panel.status_read('locked')}")

        await panel.control_write("still", 0)
        moving = await self.settled_rates()
        print("--- DDR output driving the pin")
        good = self.report("fabric", moving["fabric"], self.expected_hz)
        good = self.report("loopback", moving["loopback"],
                           self.expected_hz) and good

        await panel.control_write("still", 1)
        stopped = await self.settled_rates()
        print("--- both halves of the DDR output held equal")
        print(f"   fabric: {stopped['fabric']} Hz")
        print(f" loopback: {stopped['loopback']} Hz")
        if stopped["loopback"] > moving["loopback"] / 100:
            print("the pin did not stop when the block was told to hold it:"
                  " the rate above is not this pin's")
            good = False

        await panel.control_write("still", 0)
        await panel.control_write("led", 0x55)
        await self.session.close()
        return 0 if good else 1


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Rates.DEFAULT_PATH
    if await Rates(path).run():
        raise SystemExit(1)
