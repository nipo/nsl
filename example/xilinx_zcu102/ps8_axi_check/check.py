#!/usr/bin/env python3
"""Run the PS8 AXI port memory testers and check memory contents.

Usage:
    python check.py <jtag-chain-path>

The PL must be loaded.  Everything goes through the DAP AXI-AP: PS
setup (resets, PL power-up, PL clock 0, AXI widths, PL reset), the
test register map behind M_AXI_HPM0_LPD, and readback of OCM and of
the RAM behind M_AXI_HPM0_FPD.
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
        return b"".join(cls.beat(seed, (base + off) & cls.MASK, beat_bytes)
                        for off in range(0, size, beat_bytes))


class Ps8AxiCheck:
    PS_REF_CLK = 33.333e6
    PL_CLOCK_MAX = 100e6

    CRL_IOPLL_CTRL = 0xff5e0020
    CRL_PL0_REF_CTRL = 0xff5e00c0
    CRL_RST_LPD_IOU2 = 0xff5e0238
    CRL_RST_LPD_TOP = 0xff5e023c
    CRF_RST_FPD_TOP = 0xfd1a0100
    PMU_REQ_PWRUP_STATUS = 0xffd80110
    PMU_REQ_PWRUP_INT_EN = 0xffd80118
    PMU_REQ_PWRUP_TRIG = 0xffd80120
    FPD_SLCR_AFI_FS = 0xfd615000
    LPD_SLCR_AFI_FS = 0xff419000
    GPIO_DATA_5 = 0xff0a0054
    GPIO_DIRM_5 = 0xff0a0344
    GPIO_OEN_5 = 0xff0a0348

    RST_LPD_IOU2_GPIO = 1 << 18
    RST_LPD_TOP_FPD = 1 << 23
    RST_LPD_TOP_OCM = 1 << 3
    RST_LPD_TOP_AFI_FM6 = 1 << 19
    RST_FPD_TOP_AFI_FM = 0x1f80
    PWRUP_PL = 1 << 23
    PL_RESET_0 = 1 << 31

    REGS = 0x80000000
    REG_CONTROL = 0
    REG_STATUS = 1

    SEED = 1
    PORTS = (
        # name, base, size, beat bytes, AFIFM index
        ("S_AXI_LPD", 0xfffc0000, 0x10000, 16, 6),
        ("S_AXI_HPC0", 0xfffd0000, 0x10000, 8, 0),
        ("S_AXI_HP0", 0xfffe0000, 0x10000, 4, 2),
        ("S_AXI_HPC1 loop", 0xa0000000, 0x1000, 16, 1),
    )

    # M_AXI_HPM0_FPD is 64-bit, M_AXI_HPM0_LPD 32-bit.
    FPD_AFI_FS = (0x00000f00, 1 << 8 | 2 << 10)
    LPD_AFI_FS = (0x00000300, 0 << 8)

    def __init__(self, ap):
        self.ap = ap
        self.pl_clock = None

    async def modify(self, addr, mask, value):
        v = await self.ap.read32(addr)
        await self.ap.write32(addr, (v & ~mask) | (value & mask))

    @staticmethod
    def afifm_base(n):
        return 0xff9b0000 if n == 6 else 0xfd360000 + n * 0x10000

    @staticmethod
    def afifm_width(beat_bytes):
        return {16: 0, 8: 1, 4: 2}[beat_bytes]

    async def pl_clock_setup(self):
        iopll = await self.ap.read32(self.CRL_IOPLL_CTRL)
        if iopll & (1 << 3):
            pll = self.PS_REF_CLK
        else:
            fbdiv = (iopll >> 8) & 0x7f
            pll = self.PS_REF_CLK * fbdiv / (2 if iopll & (1 << 16) else 1)
        div0 = max(1, -int(-pll // self.PL_CLOCK_MAX))
        self.pl_clock = pll / div0
        await self.ap.write32(self.CRL_PL0_REF_CTRL,
                              1 << 24 | 1 << 16 | div0 << 8 | 0)
        print(f"IOPLL_CTRL {iopll:08x}, PL clock 0 at "
              f"{self.pl_clock / 1e6:.1f} MHz")

    async def ps_setup(self):
        await self.modify(self.CRL_RST_LPD_TOP,
                          self.RST_LPD_TOP_FPD | self.RST_LPD_TOP_OCM, 0)
        await self.modify(self.CRL_RST_LPD_IOU2, self.RST_LPD_IOU2_GPIO, 0)

        await self.modify(self.PMU_REQ_PWRUP_INT_EN, self.PWRUP_PL, self.PWRUP_PL)
        await self.modify(self.PMU_REQ_PWRUP_TRIG, self.PWRUP_PL, self.PWRUP_PL)
        deadline = time.monotonic() + 2
        while await self.ap.read32(self.PMU_REQ_PWRUP_STATUS) & self.PWRUP_PL:
            if time.monotonic() > deadline:
                raise RuntimeError("PL power-up request not serviced")
            await asyncio.sleep(0.01)

        await self.pl_clock_setup()

        await self.modify(self.CRF_RST_FPD_TOP, self.RST_FPD_TOP_AFI_FM, 0)
        await self.modify(self.CRL_RST_LPD_TOP, self.RST_LPD_TOP_AFI_FM6, 0)
        await self.modify(self.FPD_SLCR_AFI_FS, *self.FPD_AFI_FS)
        await self.modify(self.LPD_SLCR_AFI_FS, *self.LPD_AFI_FS)
        for name, _, _, beat_bytes, afifm in self.PORTS:
            base = self.afifm_base(afifm)
            for off in (0x00, 0x14):
                await self.modify(base + off, 3, self.afifm_width(beat_bytes))
            print(f"{name} AFIFM{afifm}: "
                  f"{await self.ap.read32(base):08x} "
                  f"{await self.ap.read32(base + 0x14):08x}")

        # PL reset 0 is EMIO GPIO 95, bank 5 bit 31: pulse it low.
        await self.modify(self.GPIO_DIRM_5, self.PL_RESET_0, self.PL_RESET_0)
        await self.modify(self.GPIO_OEN_5, self.PL_RESET_0, self.PL_RESET_0)
        await self.modify(self.GPIO_DATA_5, self.PL_RESET_0, 0)
        await asyncio.sleep(0.01)
        await self.modify(self.GPIO_DATA_5, self.PL_RESET_0, self.PL_RESET_0)

    async def reg_read(self, no):
        return await self.ap.read32(self.REGS + 4 * no)

    async def reg_write(self, no, value):
        await self.ap.write32(self.REGS + 4 * no, value)

    async def fill(self, value):
        for _, base, size, _, _ in self.PORTS:
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
        for i, (name, _, size, _, _) in enumerate(self.PORTS):
            errors = await self.reg_read(2 + 3 * i)
            first = await self.reg_read(3 + 3 * i)
            cycles = await self.reg_read(4 + 3 * i)
            # Written then read back once.
            rate = 2 * size * self.pl_clock / cycles / 1e6
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
        for name, base, size, beat_bytes, _ in self.PORTS:
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

    ok = await Ps8AxiCheck(ap).run()
    print("PASS" if ok else "FAIL")
    await shutdown()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(main())
