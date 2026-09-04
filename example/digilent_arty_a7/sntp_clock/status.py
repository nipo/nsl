"""Dump the SNTP clock observer panel once.

Run with::

  acrobe run status.py [resource-path]

The default path reaches the rack through the Digilent JTAG cable of
the Arty A7.
"""

import datetime
import sys

from acrobe_plugin.gatecap.session import Session


class PanelDump:
    DEFAULT_PATH = "dig-/jtag/chain/0/bnoc_continuous_transport/gatecap"
    UNIX_EPOCH = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)

    def __init__(self, path):
        self.session = Session(path)

    @staticmethod
    def ipv4(value):
        return ".".join(str((value >> shift) & 0xff) for shift in (24, 16, 8, 0))

    @classmethod
    def unix_date(cls, seconds):
        return cls.UNIX_EPOCH + datetime.timedelta(seconds=seconds)

    async def run(self):
        await self.session.open()
        panel = self.session.block_by_name("panel")

        link_up = await panel.status_read("link_up")
        dhcp_lease = await panel.status_read("dhcp_lease")
        sntp_valid = await panel.status_read("sntp_valid")
        address = await panel.status_read("address")
        ntp_server = await panel.status_read("ntp_server")
        ntp_date = await panel.status_read("ntp_date")

        print(f"link up: {bool(link_up)}")
        print(f"dhcp lease: {bool(dhcp_lease)}, address {self.ipv4(address)}")
        print(f"ntp server: {self.ipv4(ntp_server)}")
        print(f"sntp valid: {bool(sntp_valid)}, "
              f"date {ntp_date:#010x} = {self.unix_date(ntp_date).isoformat()}")


async def main():
    path = sys.argv[1] if len(sys.argv) > 1 else PanelDump.DEFAULT_PATH
    await PanelDump(path).run()
