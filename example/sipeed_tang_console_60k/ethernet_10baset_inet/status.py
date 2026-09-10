"""Dump the 10BASE-T observer panel.

Run with::

  acrobe run status.py [resource-path]
"""

import sys

from acrobe_plugin.gatecap.session import Session


class PanelDump:
    DEFAULT_PATH = ("tty-cu.usbserial-20250414201/serial(rate=1000000)"
                    "/hdlc/addr00/gatecap")

    def __init__(self, path):
        self.session = Session(path)

    @staticmethod
    def ipv4(value):
        return ".".join(str((value >> shift) & 0xff) for shift in (24, 16, 8, 0))

    async def run(self):
        await self.session.open()
        panel = self.session.block_by_name("panel")

        link_up = await panel.status_read("link_up")
        dhcp_valid = await panel.status_read("dhcp_valid")
        address = await panel.status_read("address")
        netmask = await panel.status_read("netmask")
        router = await panel.status_read("router")
        dns = await panel.status_read("dns")
        rx_frames = await panel.status_read("rx_frames")
        rx_clean = await panel.status_read("rx_clean")
        tx_frames = await panel.status_read("tx_frames")
        collisions = await panel.status_read("collisions")
        late = await panel.status_read("late_collisions")
        excessive = await panel.status_read("excessive_collisions")

        print(f"link up     : {bool(link_up)}")
        print(f"dhcp lease  : {bool(dhcp_valid)}")
        print(f"address     : {self.ipv4(address)}")
        print(f"netmask     : {self.ipv4(netmask)}")
        print(f"router      : {self.ipv4(router)}")
        print(f"dns         : {self.ipv4(dns)}")
        print(f"rx frames   : {rx_frames}")
        print(f"rx accepted : {rx_clean}")
        print(f"tx frames   : {tx_frames}")
        print(f"collisions  : {collisions}")
        print(f"late coll.  : {late}")
        print(f"excess coll.: {excessive}")


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else PanelDump.DEFAULT_PATH
    await PanelDump(path).run()
