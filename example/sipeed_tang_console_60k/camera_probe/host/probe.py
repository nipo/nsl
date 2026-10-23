"""Says which sensor sits on a PMOD-DVP plugged into a Tang Console 60k
running camera_probe.

    acrobe run probe.py

Lists what answers on the SCCB bus, then reads the identification
registers of the sensors a module like this one is sold with.  If
nothing answers at all, press S1 on the board, which swaps the rows
of the connector the camera's control lines land on, and run it again.
"""

from __future__ import annotations

import os
import sys

import ausb
import cbor2

sys.path.insert(0, os.path.join(os.path.dirname(__file__),
                                "..", "..", "sd_cbor", "host"))
from link import FramedLink  # noqa: E402

VENDOR_ID = 0xdead
PRODUCT_ID = 0x12c0


class AddressNack(Exception):
    pass


class DataNack(Exception):
    pass


class Sccb:
    """Bus operations of nsl_i2c.cbor_transactor, one batch per call.

    SCCB has no repeated start, so every write and every read is a
    transfer of its own with a stop behind it.
    """

    def __init__(self, link):
        self.link = link

    async def run(self, ops):
        """ops is a list of ("w", saddr, bytes) or ("r", saddr, count);
        the answer is one item per op: None, bytes, or an exception."""
        cmd = bytearray(b"\x9f")
        for kind, saddr, arg in ops:
            cmd += cbor2.dumps([saddr, bytes(arg) if kind == "w" else arg])
            cmd += cbor2.dumps(None)
        cmd += b"\xff"

        rsp = cbor2.loads(await self.link.exchange(bytes(cmd)),
                          semantic_decoders={2: lambda d, v: cbor2.CBORTag(2, v)})
        out = []
        for value in rsp:
            if value is False:
                out.append(AddressNack())
            elif isinstance(value, cbor2.CBORTag) and value.tag == 2:
                out.append(DataNack(value.value))
            else:
                out.append(value)
        return out

    async def scan(self):
        addrs = range(0x08, 0x78)
        rsp = await self.run([("r", a, 1) for a in addrs])
        return [a for a, v in zip(addrs, rsp) if isinstance(v, bytes)]

    async def read16(self, saddr, reg, count):
        rsp = await self.run([("w", saddr, reg.to_bytes(2, "big")),
                              ("r", saddr, count)])
        return rsp[-1]

    async def read8(self, saddr, reg, count, bank=None):
        ops = []
        if bank is not None:
            ops.append(("w", saddr, bytes([0xff, bank])))
        ops += [("w", saddr, bytes([reg])), ("r", saddr, count)]
        return (await self.run(ops))[-1]


# (name, 7-bit address, how to read the id, what it reads as)
SENSORS = (
    ("OV5640", 0x3c, lambda s: s.read16(0x3c, 0x300a, 2), b"\x56\x40"),
    ("OV2640", 0x30, lambda s: s.read8(0x30, 0x0a, 2, bank=1), b"\x26\x42"),
    ("OV7670/OV7725", 0x21, lambda s: s.read8(0x21, 0x0a, 2), None),
    ("GC0328", 0x21, lambda s: s.read8(0x21, 0xf0, 1), b"\x9d"),
    ("GC2145", 0x3c, lambda s: s.read8(0x3c, 0xf0, 2), b"\x21\x45"),
)


async def main():
    sys.stdout.reconfigure(line_buffering=True)

    async with ausb.Context() as context:
        link = await FramedLink.open(context, vendor_id=VENDOR_ID,
                                     product_id=PRODUCT_ID)
        try:
            sccb = Sccb(link)

            found = await sccb.scan()
            if not found:
                print("Nothing answers.  Press S1 and run this again.")
                return
            print("Answering:", " ".join(f"0x{a:02x}" for a in found))

            for name, saddr, read, expected in SENSORS:
                if saddr not in found:
                    continue
                value = await read(sccb)
                if isinstance(value, Exception):
                    print(f"  {name:14s} @0x{saddr:02x}: {type(value).__name__}")
                    continue
                verdict = ""
                if expected is not None:
                    verdict = "  <-- match" if value == expected else ""
                print(f"  {name:14s} @0x{saddr:02x}: id {value.hex(' ')}{verdict}")
        finally:
            await link.close()
