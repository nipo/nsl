#!/usr/bin/env python3.13
"""Measure DDR bandwidth of PS7 HP ports, direct and through the NSL
AXI crossbar.

Usage:
    python3.13 check.py <jtag-chain-path> halt
    python3.13 check.py <jtag-chain-path> run

Let boot software initialize the DDR controller, then halt both
Cortex-A9 through the debug APB-AP with "halt", so that they keep out
of the way and stop touching the PL.  "halt" also disables PS-PL
level shifters, for the PL to be reconfigured safely.  Load this design in the PL,
then "run" drives everything through the DAP AHB-AP.
"""

import asyncio
import struct
import sys
import time

from acrobe import shutdown
from acrobe.component.arm.dp import Dp, Abort
from acrobe.component.arm.mem_ap import MemAp
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


class CortexA9Halt:
    """Halts Cortex-A9 cores through their memory-mapped debug
    registers, as seen from the debug APB-AP."""

    CORE_BASES = (0x80090000, 0x80092000)
    DBGDSCR = 0x088
    DBGDRCR = 0x090
    DBGOSLAR = 0x300
    DBGLAR = 0xfb0

    DSCR_HALTED = 1 << 0
    DSCR_HDBGEN = 1 << 14
    DRCR_HRQ = 1 << 0

    def __init__(self, ap):
        self.ap = ap

    async def halt(self):
        for no, base in enumerate(self.CORE_BASES):
            await self.ap.write32(base + self.DBGLAR, 0xc5acce55)
            await self.ap.write32(base + self.DBGOSLAR, 0)
            dscr = await self.ap.read32(base + self.DBGDSCR)
            await self.ap.write32(base + self.DBGDSCR, dscr | self.DSCR_HDBGEN)
            await self.ap.write32(base + self.DBGDRCR, self.DRCR_HRQ)

            deadline = time.monotonic() + 1
            while True:
                dscr = await self.ap.read32(base + self.DBGDSCR)
                if dscr & self.DSCR_HALTED:
                    break
                if time.monotonic() > deadline:
                    raise RuntimeError(f"CPU{no} does not halt, DSCR {dscr:08x}")
                await asyncio.sleep(0.01)
            print(f"CPU{no} halted, DSCR {dscr:08x}")


class Ps7DdrBandwidth:
    SLCR_UNLOCK = 0xf8000008
    FPGA_RST_CTRL = 0xf8000240
    LVL_SHFTR_EN = 0xf8000900
    AFI_BASE = 0xf8008000
    AFI_STRIDE = 0x1000
    AFI_RDCHAN_CTRL = 0x00
    AFI_WRCHAN_CTRL = 0x14
    AFI_USED = (0, 1, 2)

    REGS = 0x80000000
    REG_CONTROL = 0
    REG_STATUS = 1

    CLOCK = 125e6
    BEAT_BYTES = 8
    REGION_BASE = 0x10000000
    REGION_SIZE = 0x1000000
    TESTERS = ("xbar HP0 m0", "xbar HP0 m1", "HP1", "HP2")

    SCENARIOS = (
        ("HP1 alone", (2,)),
        ("HP1 + HP2", (2, 3)),
        ("crossbar, one master", (0,)),
        ("crossbar, two masters", (0, 1)),
        ("all four", (0, 1, 2, 3)),
    )

    # Spots read back through the DAP; the whole region would take
    # minutes.  Testers check every beat anyway.
    SAMPLE_OFFSETS = (0, 0x7ff800, 0xfff800)
    SAMPLE_SIZE = 0x800

    def __init__(self, ap):
        self.ap = ap

    async def reg_read(self, no):
        return await self.ap.read32(self.REGS + 4 * no)

    async def reg_write(self, no, value):
        await self.ap.write32(self.REGS + 4 * no, value)

    async def pl_isolate(self):
        # Keep PL outputs away from the PS while the PL is
        # reconfigured: a glitch on an HP port leaves its AFI with
        # stray write data, and only a PS reset clears it.
        await self.ap.write32(self.SLCR_UNLOCK, 0xdf0d)
        await self.ap.write32(self.FPGA_RST_CTRL, 0xf)
        await self.ap.write32(self.LVL_SHFTR_EN, 0)

    async def ps_setup(self):
        await self.ap.write32(self.SLCR_UNLOCK, 0xdf0d)
        await self.ap.write32(self.LVL_SHFTR_EN, 0xf)
        await self.ap.write32(self.FPGA_RST_CTRL, 0)

        # AFI registers live in the port clock domain, PL clock must run.
        for afi in self.AFI_USED:
            for off in (self.AFI_RDCHAN_CTRL, self.AFI_WRCHAN_CTRL):
                addr = self.AFI_BASE + afi * self.AFI_STRIDE + off
                v = await self.ap.read32(addr)
                await self.ap.write32(addr, v & ~1)

    def tester_base(self, i):
        return self.REGION_BASE + i * self.REGION_SIZE

    async def run_scenario(self, name, testers):
        enable = sum(1 << i for i in testers)
        await self.reg_write(self.REG_CONTROL, 0)
        for i in testers:
            await self.ap.mem_write(self.tester_base(i), b"\xa5" * self.SAMPLE_SIZE)
        await self.reg_write(self.REG_CONTROL, enable)
        await self.reg_write(self.REG_CONTROL, enable | (enable << 8))

        done = sum(2 << (2 * i) for i in testers)
        deadline = time.monotonic() + 5
        while True:
            status = await self.reg_read(self.REG_STATUS)
            if status & done == done:
                break
            if time.monotonic() > deadline:
                raise RuntimeError(f"{name}: testers stuck, status {status:08x}")
            await asyncio.sleep(0.05)

        print(f"{name}:")
        ok = True
        total_w = total_r = 0
        for i in testers:
            errors = await self.reg_read(2 + 4 * i)
            first = await self.reg_read(3 + 4 * i)
            w_cycles = await self.reg_read(4 + 4 * i)
            r_cycles = await self.reg_read(5 + 4 * i)
            w_rate = self.REGION_SIZE * self.CLOCK / w_cycles / 1e6
            r_rate = self.REGION_SIZE * self.CLOCK / r_cycles / 1e6
            total_w += w_rate
            total_r += r_rate
            print(f"  {self.TESTERS[i]:12s} write {w_rate:6.0f} MB/s, "
                  f"read {r_rate:6.0f} MB/s, {errors} errors"
                  + (f", first at {first:08x}" if errors else ""))
            ok = ok and errors == 0
            ok = await self.check_samples(i) and ok
        if len(testers) > 1:
            print(f"  {'total':12s} write {total_w:6.0f} MB/s, "
                  f"read {total_r:6.0f} MB/s")
        return ok

    async def check_samples(self, i):
        ok = True
        for off in self.SAMPLE_OFFSETS:
            addr = self.tester_base(i) + off
            got = await self.ap.mem_read(addr, self.SAMPLE_SIZE)
            want = Pattern.region(i + 1, addr, self.SAMPLE_SIZE, self.BEAT_BYTES)
            if got != want:
                bad = sum(got[j:j + 4] != want[j:j + 4]
                          for j in range(0, self.SAMPLE_SIZE, 4))
                print(f"  {self.TESTERS[i]}: {bad} bad words at {addr:08x}")
                ok = False
        return ok

    async def run(self):
        await self.ps_setup()
        ok = True
        for name, testers in self.SCENARIOS:
            ok = await self.run_scenario(name, testers) and ok
        return ok


async def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("halt", "run"):
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    leaf = await root(sys.argv[1])
    await leaf.start_tree()
    dp = leaf.children_of_class(Dp, include_self=True)[0]
    await dp.post(Abort(dp.ABORT_ALL))

    if sys.argv[2] == "halt":
        # APB-AP (IDR.TYPE 2) carries the CoreSight debug bus.
        debug_ap = next(ap for ap in dp.children_of_class(MemAp)
                        if (ap.idr or 0) & 0xf == 2)
        await CortexA9Halt(debug_ap).halt()
        await Ps7DdrBandwidth(dp.system_memap()).pl_isolate()
        await shutdown()
        return

    ok = await Ps7DdrBandwidth(dp.system_memap()).run()
    print("PASS" if ok else "FAIL")
    await shutdown()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    asyncio.run(main())
