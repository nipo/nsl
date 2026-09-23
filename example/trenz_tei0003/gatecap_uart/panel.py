"""Read and write the bench's panel over the board's own serial port.

Run with::

  acrobe run panel.py [resource-path]

The port carries no rate of its own -- a resource path cannot say one --
so the line is set to the rate the gateware was built for before the
rack is resolved.  A port left at the kernel's default is the first
thing to suspect when nothing answers.
"""

import asyncio
import sys

from acrobe.adapter.model import get_hw_root
from acrobe.protocol.serial import SerialConfig

from acrobe_plugin.gatecap.session import Session


class Panel:
    # The adapter name is the board's USB serial number as udev spells
    # it; the three segments after it are the UART, the HDLC framing the
    # transport wraps its frames in, and the rack itself.
    DEFAULT_PATH = ("tty-usb-Arrow_Arrow_USB_Blaster_TEI0003_ARA41546-if01-port0"
                    "/serial/hdlc/addr00/gatecap")

    # What the gateware's baud_rate_c says.
    BAUD_C = 1000000

    def __init__(self, path):
        self.path = path
        self.session = Session(path)

    async def line_up(self):
        """Put the tty at the gateware's rate, and in raw mode with it:
        acrobe only clears the line discipline when a configuration is
        applied, so this is what makes the port carry bytes at all."""
        adapter, port = self.path.strip("/").split("/")[:2]
        hw_root = get_hw_root()
        await hw_root.ensure_started()
        node = await hw_root.child_summon(adapter, port)
        applied = await node.config_set(SerialConfig(baud=self.BAUD_C))
        print(f"port {adapter}/{port} at {applied}")

    async def run(self):
        await self.line_up()
        fingerprint = await self.session.open()
        print(f"rack fingerprint {fingerprint:#010x}")

        for block in self.session.blocks():
            print(f"  block {block.name}")

        rates = self.session.block_by_name("rates")
        panel = self.session.block_by_name("panel")

        print(f"rates {await rates.rates()}")

        # Host to fabric and back: the value returns through a status
        # word the fabric wires the control to, so a round trip that
        # matches has crossed the register file.
        for value in (0x00000000, 0xdeadbeef, 0x5a5a5a5a, 0xffffffff):
            await panel.control_write("scratch", value)
            back = await panel.status_read("scratch_back")
            print(f"scratch {value:#010x} -> scratch_back {back:#010x}"
                  f"  {'ok' if back == value else 'MISMATCH'}")

        # The counter, read twice: the design is clocked if it moved.
        first = await panel.status_read("ticks")
        await asyncio.sleep(0.5)
        second = await panel.status_read("ticks")
        delta = (second - first) & 0xffffffff
        print(f"ticks {first} -> {second}, {delta} in about half a second")

        # The event path, the same round trip taken through ticks
        # rather than through registers.
        before = (await panel.counters_read())["ping_count"]
        for _ in range(5):
            await panel.strobe("ping")
        after = (await panel.counters_read())["ping_count"]
        print(f"ping_count {before} -> {after} after 5 strobes")

        print(f"button {await panel.status_read('button')}")

        # Leave a pattern on the LEDs, so the board says a host has
        # been here.
        await panel.control_write("led", 0x55)

        await self.session.close()
        return 0


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else Panel.DEFAULT_PATH
    return await Panel(path).run()
