"""Writes to a card and puts back what was there.

    acrobe run verify.py [--high-speed] [lba] [blocks]

Reads what the blocks hold, writes a pattern over them, reads it back,
then writes what was there before and reads that back too.  So a card
comes out of this holding what it went in holding, whether or not the
writing works.

The blocks default to a run well past the end of anything a partition
table on this card claims.  Give an address of your own only if you
know what is there.
"""

from __future__ import annotations

import sys
import time

import ausb

from card import BLOCK_SIZE, SdCard
from link import FramedLink
from transactor import SdioTransactor

# Far enough in to be past a partition table's last entry on the cards
# this gets pointed at, and not so far as to be off a small one
DEFAULT_LBA = 1000000
DEFAULT_BLOCKS = 64


def pattern(lba: int, count: int) -> bytes:
    """Something a card would not be holding by accident, and which
    says which block it came from."""
    out = bytearray()
    for i in range(count):
        block = bytearray(
            f"nsl_sdio block {lba + i} ".encode("ascii") * 32)[:BLOCK_SIZE]
        for j in range(0, BLOCK_SIZE, 64):
            block[j] = (lba + i) & 0xff
        out += block
    return bytes(out)


def differs(a: bytes, b: bytes, lba: int):
    """Where two runs of blocks stop matching, if they do."""
    for i in range(0, len(a), BLOCK_SIZE):
        if a[i:i + BLOCK_SIZE] != b[i:i + BLOCK_SIZE]:
            block = a[i:i + BLOCK_SIZE]
            other = b[i:i + BLOCK_SIZE]
            at = next(k for k in range(BLOCK_SIZE) if block[k] != other[k])
            return (lba + i // BLOCK_SIZE, at,
                    block[at:at + 16], other[at:at + 16])
    return None


async def main():
    sys.stdout.reconfigure(line_buffering=True)

    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    high_speed = "--high-speed" in sys.argv[1:]
    lba = int(args[0], 0) if args else DEFAULT_LBA
    count = int(args[1], 0) if args[1:] else DEFAULT_BLOCKS

    async with ausb.Context() as context:
        link = await FramedLink.open(context)
        sdio = SdioTransactor(link)

        info = await sdio.info()
        card = SdCard(sdio, clock_hz=info.clock_hz,
                      lane_count=info.lane_count)
        await card.identify()
        if high_speed:
            await card.high_speed()

        print(f"{card.cid.name!r}, {card.block_count} blocks,"
              f" bus at {card.bus_hz / 1e6:g} MHz over {card.width} lines")

        if lba + count > card.block_count:
            raise SystemExit(f"blocks {lba}..{lba + count - 1} are not on a"
                             f" card holding {card.block_count}")

        print(f"blocks {lba}..{lba + count - 1}\n")

        was = await card.read_run(lba, count)
        print(f"read what was there      {len(was)} bytes")

        mine = pattern(lba, count)
        start = time.monotonic()
        stored = await card.write_run(lba, mine)
        seconds = time.monotonic() - start
        print(f"wrote a pattern          {stored} blocks,"
              f" {len(mine) / seconds / 1e6:.2f} MB/s")

        back = await card.read_run(lba, count)
        bad = differs(mine, back, lba)
        if bad:
            raise SystemExit(f"block {bad[0]} byte {bad[1]}: wrote"
                             f" {bad[2].hex()}, read {bad[3].hex()}")
        print("read it back             matches")

        await card.write_run(lba, was)
        again = await card.read_run(lba, count)
        bad = differs(was, again, lba)
        if bad:
            raise SystemExit(f"putting it back failed at block {bad[0]}"
                             f" byte {bad[1]}: {bad[2].hex()}"
                             f" became {bad[3].hex()}")
        print("put back what was there  matches")

        await link.close()
