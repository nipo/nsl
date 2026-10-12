"""Dump the PTP slave observer panel.

Run with::

  acrobe run status.py gatecap-XXXXXXXX/gatecap

where the rack's name comes from ``acrobe info enumerate``.
"""

import sys

from acrobe_plugin.gatecap.session import Session


class PanelDump:
    def __init__(self, path):
        self.session = Session(path)

    @staticmethod
    def signed(value, width):
        if value & (1 << (width - 1)):
            return value - (1 << width)
        return value

    async def run(self):
        await self.session.open()
        panel = self.session.block_by_name("panel")

        link_up = await panel.status_read("link_up")
        locked = await panel.status_read("locked")
        second = await panel.status_read("second")
        offset = self.signed(await panel.status_read("offset"), 32)
        path_delay = self.signed(await panel.status_read("path_delay"), 32)
        freq_ppb = self.signed(await panel.status_read("freq_ppb"), 24)
        syncs = await panel.status_read("syncs")
        steps = await panel.status_read("steps")
        rx_frames = await panel.status_read("rx_frames")
        tx_frames = await panel.status_read("tx_frames")
        tx_stamps = await panel.status_read("tx_stamps")

        print(f"link up     : {bool(link_up)}")
        print(f"locked      : {bool(locked)}")
        print(f"second (TAI): {second}")
        print(f"offset      : {offset} ns")
        print(f"path delay  : {path_delay} ns")
        print(f"freq        : {freq_ppb} ppb")
        print(f"syncs       : {syncs}")
        print(f"steps       : {steps}")
        print(f"rx frames   : {rx_frames}")
        print(f"tx frames   : {tx_frames}")
        print(f"tx stamps   : {tx_stamps}")


async def main():
    if len(sys.argv) != 2:
        sys.exit("usage: status.py <resource-path>")
    await PanelDump(sys.argv[1]).run()
