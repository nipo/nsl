#!/usr/bin/env python3.13
"""Run the PS7 AXI port memory testers and check memory contents.

Usage:
    python3.13 check.py <jtag-chain-path>

The PL must be loaded.  Everything goes through the DAP AHB-AP: SLCR
setup, the test register map behind M_AXI_GP1, and readback of OCM
and of the RAM behind M_AXI_GP0.
"""

import asyncio
import struct
import sys
import time

from acrobe import shutdown
from acrobe.component.arm.dp import Dp, Abort
from acrobe.root import root


class Pattern:
    """Mirror of nsl_amba.mm_traffic.pattern()."""

    STEPS = (
        (16, False, 13, 0x9e3779b9),
        (9, True, 17, 0x85ebca6b),
        (13, False, 7, 0xc2b2ae35),
    )
    MASK = 0xffffffff

    @classmethod
    def mix(cls, v):
        for fold, up, turn, addend in cls.STEPS:
            v ^= ((v << fold) & cls.MASK) if up else (v >> fold)
            v = ((v << turn) | (v >> (32 - turn))) & cls.MASK
            v = (v + addend) & cls.MASK
        return v ^ (v >> 16)

    @classmethod
    def beat(cls, seed, beat_address, byte_count):
        groups = (byte_count + 3) // 4
        words = [cls.mix(beat_address ^ seed ^ ((g + 1) << 24))
                 for g in range(groups)]
        return struct.pack(f"<{groups}I", *words)[:byte_count]

    @classmethod
    def region(cls, seed, base, size, beat_bytes):
        return b"".join(cls.beat(seed, base + off, beat_bytes)
                        for off in range(0, size, beat_bytes))


class Ps7AxiCheck:
    SLCR_UNLOCK = 0xf8000008
    FPGA_RST_CTRL = 0xf8000240
    LVL_SHFTR_EN = 0xf8000900
    AFI_BASE = 0xf8008000
    AFI_STRIDE = 0x1000
    AFI_RDCHAN_CTRL = 0x00
    AFI_WRCHAN_CTRL = 0x14

    REGS = 0x80000000
    REG_CONTROL = 0
    REG_STATUS = 1

    SEED = 1
    PORTS = (
        # name, base, size, beat bytes, AFI index, AFI 32-bit mode
        ("HP0", 0x00000, 0x10000, 4, 0, True),
        ("HP1", 0x10000, 0x10000, 8, 1, False),
        ("ACP", 0x20000, 0x10000, 8, None, False),
        ("GP0 loop", 0x40000000, 0x1000, 4, None, False),
    )

    def __init__(self, ap):
        self.ap = ap

    async def reg_read(self, no):
        return await self.ap.read32(self.REGS + 4 * no)

    async def reg_write(self, no, value):
        await self.ap.write32(self.REGS + 4 * no, value)

    async def ps_setup(self):
        await self.ap.write32(self.SLCR_UNLOCK, 0xdf0d)
        await self.ap.write32(self.LVL_SHFTR_EN, 0xf)
        await self.ap.write32(self.FPGA_RST_CTRL, 0)

        # AFI registers live in the port clock domain, PL clock must run.
        for name, _, _, _, afi, narrow in self.PORTS:
            if afi is None:
                continue
            for off in (self.AFI_RDCHAN_CTRL, self.AFI_WRCHAN_CTRL):
                addr = self.AFI_BASE + afi * self.AFI_STRIDE + off
                v = await self.ap.read32(addr)
                v = (v | 1) if narrow else (v & ~1)
                await self.ap.write32(addr, v)
                print(f"{name} AFI +{off:02x}: {await self.ap.read32(addr):08x}")

    async def fill(self, value):
        for _, base, size, _, _, _ in self.PORTS:
            blob = bytes([value]) * size
            for off in range(0, size, 2048):
                await self.ap.mem_write(base + off, blob[off:off + 2048])

    async def read(self, base, size):
        out = bytearray()
        for off in range(0, size, 2048):
            out += await self.ap.mem_read(base + off, 2048)
        return bytes(out)

    async def run_testers(self):
        count = len(self.PORTS)
        enable = (1 << count) - 1
        await self.reg_write(self.REG_CONTROL, 0)
        await self.reg_write(self.REG_CONTROL, enable)
        await self.reg_write(self.REG_CONTROL, enable | (enable << 8))

        done = sum(2 << (2 * i) for i in range(count))
        deadline = time.monotonic() + 5
        while True:
            status = await self.reg_read(self.REG_STATUS)
            if status & done == done:
                break
            if time.monotonic() > deadline:
                raise RuntimeError(f"testers stuck, status {status:08x}")
            await asyncio.sleep(0.05)

        ok = True
        for i, (name, _, size, _, _, _) in enumerate(self.PORTS):
            errors = await self.reg_read(2 + 3 * i)
            first = await self.reg_read(3 + 3 * i)
            cycles = await self.reg_read(4 + 3 * i)
            # Written then read back once.
            rate = 2 * size * 125e6 / cycles / 1e6
            print(f"{name}: {errors} errors, first at {first:08x}, "
                  f"{cycles} cycles ({rate:.0f} MB/s)")
            ok = ok and errors == 0
        return ok

    def compare(self, name, base, got, want):
        if got == want:
            print(f"{name}: memory matches pattern")
            return True
        bad = [i for i in range(0, len(got), 4) if got[i:i + 4] != want[i:i + 4]]
        print(f"{name}: {len(bad)} mismatching words out of {len(got) // 4}")
        for i in bad[:8]:
            print(f"  {base + i:08x}: got {got[i:i + 4].hex()} "
                  f"want {want[i:i + 4].hex()}")
        # Look up where the expected words ended up, to tell a lane or
        # stride swap from garbage.
        index = {want[j:j + 4]: j for j in range(0, len(want), 4)}
        for i in bad[:8]:
            j = index.get(got[i:i + 4])
            if j is not None:
                print(f"  {base + i:08x} holds the word expected at {base + j:08x}")
        return False

    async def run(self):
        await self.ps_setup()
        await self.fill(0xa5)
        ok = await self.run_testers()
        for name, base, size, beat_bytes, _, _ in self.PORTS:
            got = await self.read(base, size)
            want = Pattern.region(self.SEED, base, size, beat_bytes)
            ok = self.compare(name, base, got, want) and ok
        return ok


async def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    leaf = await root(sys.argv[1])
    await leaf.start_tree()
    dp = leaf.children_of_class(Dp, include_self=True)[0]
    await dp.post(Abort(dp.ABORT_ALL))
    ap = dp.system_memap()

    ok = await Ps7AxiCheck(ap).run()
    print("PASS" if ok else "FAIL")
    await shutdown()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(main())
