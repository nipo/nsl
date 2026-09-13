"""Walks the card in the socket of a Tang Console 60k running sd_cbor.

    acrobe run walk.py [--high-speed] [block ...]

Brings the card up, says what it is, and reads what is asked for: the
first block by default, which on a formatted card holds a partition
table.
"""

from __future__ import annotations

import sys

import ausb

from card import BLOCK_SIZE, SdCard, SdMemory
from link import FramedLink
from transactor import SdioTransactor


def hexdump(data: bytes, base: int = 0):
    for off in range(0, len(data), 16):
        row = data[off:off + 16]
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in row)
        print(f"{base + off:08x}  {row.hex(' ', 1):<47}  |{text}|")


def partitions(mbr: bytes):
    """Entries of a partition table, if what was read is one."""
    if mbr[510:512] != b"\x55\xaa":
        return []

    out = []
    for i in range(4):
        entry = mbr[446 + i * 16:462 + i * 16]
        kind = entry[4]
        if not kind:
            continue
        start = int.from_bytes(entry[8:12], "little")
        count = int.from_bytes(entry[12:16], "little")
        out.append((i, kind, start, count, bool(entry[0] & 0x80)))
    return out


async def main():
    # Rounds come out as they happen rather than when this ends, which
    # matters when a card is slow or a read goes wrong
    sys.stdout.reconfigure(line_buffering=True)

    args = [a for a in sys.argv[1:] if a != "--high-speed"]
    high_speed = "--high-speed" in sys.argv[1:]
    blocks = [int(a, 0) for a in args] or [0]

    async with ausb.Context() as context:
        link = await FramedLink.open(context)
        sdio = SdioTransactor(link)

        info = await sdio.info()
        print(f"host: spec {info.version}, {info.clock_hz / 1e6:g} MHz fabric,"
              f" {info.lane_count} lines,"
              f" blocks up to {info.max_block_size} bytes")

        lines = await sdio.lines()
        print(f"bus: card {'in' if lines.card_present else 'out'},"
              f" cmd {int(lines.cmd)}, dat {lines.dat:#x},"
              f" {'busy' if lines.busy else 'idle'}")

        card = SdCard(sdio, clock_hz=info.clock_hz,
                      lane_count=info.lane_count)
        await card.identify()
        if high_speed:
            await card.high_speed()

        print(f"card: {card.cid}")
        print(f"      csd v{card.csd.version + 1}, {card.block_count} blocks,"
              f" {card.csd.capacity / 1e9:.2f} GB,"
              f" {'block' if card.high_capacity else 'byte'} addressed")
        print(f"      bus at {card.bus_hz / 1e6:g} MHz"
              f" over {card.width} lines")

        # The card as an address space, which is what a walk goes over
        memory = SdMemory(card)
        print(f"      {memory.size} bytes of address space")

        for lba in blocks:
            print(f"\nblock {lba}:")
            data = await memory.mem_read(lba * BLOCK_SIZE, BLOCK_SIZE)
            hexdump(data, lba * BLOCK_SIZE)

            if lba:
                continue

            table = partitions(data)
            if not table:
                continue

            print("\npartition table:")
            for i, kind, start, count, boot in table:
                print(f"  {i}: type {kind:#04x} at block {start}"
                      f" for {count} blocks"
                      f" ({count * BLOCK_SIZE / 1e9:.2f} GB)"
                      f"{' boot' if boot else ''}")
                head = await memory.mem_read(start * BLOCK_SIZE, 64)
                hexdump(head, start * BLOCK_SIZE)

        await link.close()
