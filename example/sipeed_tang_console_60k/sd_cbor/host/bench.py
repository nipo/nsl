"""How fast blocks come off the card.

    acrobe run bench.py [megabytes]

Reads a run of blocks in batches of a few sizes and says what each
came to.  A batch is one round trip, so the smaller ones say what the
round trip costs and the larger ones what the bus does.
"""

from __future__ import annotations

import sys
import time

import ausb

from card import BLOCK_SIZE, SdCard
from link import FramedLink
from transactor import SdioTransactor

# Blocks per batch, and batches kept in the air at once
RUNS = ((1, 1), (64, 1), (64, 2), (256, 2), (1024, 2))


async def measure(card, per_batch, depth, total_blocks, lba=0):
    start = time.monotonic()
    data = await card.read_run(lba, total_blocks,
                               per_batch=per_batch, depth=depth)
    seconds = time.monotonic() - start
    if len(data) != total_blocks * BLOCK_SIZE:
        raise IOError(f"asked for {total_blocks} blocks,"
                      f" got {len(data)} bytes")
    return len(data), seconds


async def main():
    sys.stdout.reconfigure(line_buffering=True)
    args = [a for a in sys.argv[1:] if a != "--high-speed"]
    high_speed = "--high-speed" in sys.argv[1:]
    megabytes = float(args[0]) if args else 4.0
    total = int(megabytes * 1e6) // BLOCK_SIZE

    async with ausb.Context() as context:
        link = await FramedLink.open(context)
        sdio = SdioTransactor(link)

        info = await sdio.info()
        card = SdCard(sdio, clock_hz=info.clock_hz,
                      lane_count=info.lane_count)
        await card.identify()
        if high_speed:
            await card.high_speed()

        print(f"{card.cid.name!r}, bus at {card.bus_hz / 1e6:g} MHz"
              f" over {card.width} lines")
        print(f"reading {total} blocks per run\n")
        print(f"{'blocks/batch':>12}  {'in flight':>9}  {'MB/s':>7}"
              f"  {'Mb/s':>7}  {'ms/batch':>9}")

        for per_batch, depth in RUNS:
            size, seconds = await measure(card, per_batch, depth, total)
            rate = size / seconds
            batches = total / per_batch
            print(f"{per_batch:>12}  {depth:>9}  {rate / 1e6:>7.2f}"
                  f"  {rate * 8 / 1e6:>7.1f}  {seconds / batches * 1e3:>9.2f}")

        await link.close()
