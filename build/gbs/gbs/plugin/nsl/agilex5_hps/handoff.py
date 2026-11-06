"""HPS boot configuration handed over by the SDM.

Quartus takes it from the HPS_ISW_DATA global assignment and stores it
in the bitstream, where the first stage boot loader finds it.  Entries
come in the order the vendor IP (sm_handoff.tcl, render_qip_data) emits
them.
"""

from __future__ import annotations

from pathlib import Path

from .config import HpsConfig


class Handoff:
    """HPS_ISW_DATA content of a configuration"""

    # Peripheral power gate bits, set for unused peripherals
    POWER_GATE = {
        "usb0": 1 << 0,
        "usb1": 1 << 1,
        "emac0": 1 << 2,
        "emac1": 1 << 3,
        "emac2": 1 << 4,
        "nand": 1 << 5,
        "sdmmc": 1 << 6,
        "coresight": 1 << 7,
    }
    # NAND combo PHY select, set when NAND is in use
    NAND_PHY_SELECT = 1 << 16

    def __init__(self, config: HpsConfig):
        self.config = config

    def cores_power(self) -> int:
        cpu = self.config.cpu
        return 3 * cpu.a55 + 4 * cpu.a76_core2 + 8 * cpu.a76_core3

    def peripherals_power_gate(self) -> int:
        gate = 0
        for name, bit in self.POWER_GATE.items():
            if name not in self.config.peripherals:
                gate |= bit
        if "nand" in self.config.peripherals:
            gate |= self.NAND_PHY_SELECT
        return gate

    def entries(self) -> list[tuple[str, str, str]]:
        c = self.config
        e = [
            ("SDM", "DDR", str(int(c.emif_topology is not None))),
            # Bit 0 tells two channels on one IO96B, bit 1 two IO96B, none
            # of the supported topologies has them.
            ("ddr", "IO96B_CSR", "0"),
            ("SDM", "WACH", c.WATCHDOG_RESETS[c.watchdog_reset]),
            ("pwr", "core", str(self.cores_power())),
            ("pwr", "boot", str(c.cpu.boot_core)),
            ("pwr", "l3", str(c.cpu.l3_cache_mb)),
            ("pwr", "periphs", str(self.peripherals_power_gate())),
            ("intfcsel", "f2soc", str(int("f2h" in c.bridges))),
            ("intfcsel", "f2sdram", str(int("f2sdram" in c.bridges))),
        ]
        e += [("use", f"csr.pinmux_{name}_usefpga.sel", str(int(name in c.use_fpga)))
              for name in c.USE_FPGA]
        e += [("sel", str(i), str(p.select)) for i, p in enumerate(c.pins)]
        e += [("din", str(i), str(p.input_delay)) for i, p in enumerate(c.pins)]
        e += [("dou", str(i), str(p.output_delay)) for i, p in enumerate(c.pins)]
        e += [("pll", k, str(v)) for k, v in c.clock_manager.items()]
        return e

    def isw_data(self) -> str:
        return "".join(f" {a} {b} {v}" for a, b, v in self.entries())

    def tcl(self) -> str:
        """Quartus project assignment"""
        return ("# HPS boot configuration, generated from "
                f"{Path(self.config.origin).name}\n"
                f'set_global_assignment -name HPS_ISW_DATA "{self.isw_data()}"\n')
