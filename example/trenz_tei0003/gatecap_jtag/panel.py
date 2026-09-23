"""Read and write the bench's panel over the part's own TAP.

Run with::

  acrobe run panel.py [resource-path]
"""

import asyncio
import sys

from acrobe_plugin.gatecap.session import Session


class Panel:
    # After the chain come the SLD hub, the node it reports as a gatecap
    # continuous transport, and the rack itself.
    DEFAULT_PATH = "tei-ara41546/jtag/chain/0/sld/continuous_transport/gatecap"

    def __init__(self, path):
        self.path = path
        self.session = Session(path)

    async def run(self):
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
