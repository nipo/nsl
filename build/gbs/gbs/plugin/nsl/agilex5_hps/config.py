"""Agilex 5 HPS configuration file (file type nsl-agilex5-hps).

A YAML document describing the HPS of a design: processor, peripherals,
HPS IO pins, bridges in use, HPS memory and clock manager settings.
Nothing is computed: clock manager values are the ones the vendor IP
would hand over to the boot firmware for the same settings.  Every key
is checked, unknown or missing ones are errors.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml


class HpsConfigError(Exception):
    """Invalid HPS configuration file"""


@dataclass(frozen=True)
class Bridge:
    data_width: int
    address_width: int


@dataclass(frozen=True)
class Pin:
    select: int
    mode: str
    input_delay: int
    output_delay: int

    def has_input(self) -> bool:
        return self.mode in ("input", "bidir", "bidir_open_drain", "i2c")

    def has_output(self) -> bool:
        return self.mode in ("output", "bidir", "bidir_open_drain", "i2c")


@dataclass(frozen=True)
class Cpu:
    a55: bool
    a76_core2: bool
    a76_core3: bool
    boot_core: int
    l3_cache_mb: int
    mpu_frequency_hz: int


class HpsConfig:
    """Parsed and checked HPS configuration"""

    PIN_COUNT = 48
    PIN_MODES = ("unused", "input", "output", "bidir", "bidir_open_drain", "i2c")
    PERIPHERALS = ("usb0", "usb1", "emac0", "emac1", "emac2", "nand", "sdmmc", "coresight")
    WATCHDOG_RESETS = {"cold": "COLD", "warm": "WARM", "remote_update": "C_RSU"}
    EMIF_TOPOLOGIES = ("1x16", "1x32")

    # Bridge name -> (allowed data widths, max address width)
    BRIDGES = {
        "h2f": ((32, 64, 128), 38),
        "lwh2f": ((32,), 29),
        "f2h": ((256,), 40),
        "f2sdram": ((64, 128, 256), 40),
    }
    MIN_ADDRESS_WIDTH = 20

    # Pinmux usefpga entries, in handoff order
    USE_FPGA = (
        "emac0", "emac1", "emac2", "i2c0", "i2c1", "i3c0", "i3c1",
        "i2c_emac0", "i2c_emac1", "i2c_emac2", "nand", "spim0", "spim1",
        "spis0", "spis1", "uart0", "uart1", "mdio0", "mdio1", "mdio2",
        "jtag", "sdmmc",
    )

    # Clock manager entries, in handoff order
    CLOCK_MANAGER = (
        "mainpllgrp.nocclk.src", "mainpllgrp.nocdiv.cspdbgclk",
        "mainpllgrp.nocdiv.cstraceclk", "mainpllgrp.nocdiv.csclk",
        "mainpllgrp.nocdiv.mpuperiphdiv", "mainpllgrp.nocdiv.ccudiv",
        "mainpllgrp.nocdiv.softphydiv", "mainpllgrp.nocdiv.l4spclk",
        "mainpllgrp.nocdiv.l4mpclk", "mainpllgrp.nocdiv.l4sysfreeclk",
        "mainpllgrp.pllglob.modclkdiv", "mainpllgrp.pllglob.fastrefclk",
        "mainpllgrp.pllglob.psrc", "mainpllgrp.pllglob.drefclkdiv",
        "mainpllgrp.pllglob.arefclkdiv", "mainpllgrp.fdbck.fdiv",
        "mainpllgrp.pllc0.div", "mainpllgrp.pllc1.div", "mainpllgrp.pllc2.div",
        "mainpllgrp.pllc3.div", "mainpllgrp.pllm.mdiv",
        "perpllgrp.emacctl.emac0sel", "perpllgrp.emacctl.emac1sel",
        "perpllgrp.emacctl.emac2sel", "perpllgrp.pllglob.modclkdiv",
        "perpllgrp.pllglob.fstrefclk", "perpllgrp.pllglob.psrc",
        "perpllgrp.pllglob.drefclkdiv", "perpllgrp.pllglob.arefclkdiv",
        "perpllgrp.fdbck.fdiv", "perpllgrp.pllc0.div", "perpllgrp.pllc1.div",
        "perpllgrp.pllc2.div", "perpllgrp.pllc3.div", "perpllgrp.pllm.mdiv",
        "ctl.emacactr.src", "ctl.emacactr.cnt", "ctl.emacbctr.src",
        "ctl.emacbctr.cnt", "ctl.emacptpctr.src", "ctl.emacptpctr.cnt",
        "ctl.gpiodbctr.src", "ctl.gpiodbctr.cnt", "perpllgrp.gpiodiv.gpiodbclk",
        "ctl.s2fuser0ctr.src", "ctl.s2fuser0ctr.cnt", "ctl.s2fuser1ctr.src",
        "ctl.s2fuser1ctr.cnt", "ctl.psirefctr.src", "ctl.psirefctr.cnt",
        "ctl.usb31ctr.src", "ctl.usb31ctr.cnt", "ctl.dsuctr.src", "ctl.dsuctr.cnt",
        "ctl.core01ctr.src", "ctl.core01ctr.cnt", "ctl.core23ctr.src",
        "ctl.core2ctr.cnt", "ctl.core3ctr.cnt", "hps_osc_clk_hz", "fpga_clk_hz",
    )

    TOP_KEYS = {"cpu", "peripherals", "watchdog_reset", "emif", "bridges",
                "pins", "use_fpga", "clock_manager"}

    def __init__(self, data, origin: str = "<config>"):
        self.origin = origin
        top = self.mapping(data, "document")
        self.keys(top, "document", required={"cpu", "peripherals", "watchdog_reset",
                                             "pins", "clock_manager"},
                  allowed=self.TOP_KEYS)

        cpu = self.mapping(top["cpu"], "cpu")
        self.keys(cpu, "cpu", required=set(Cpu.__dataclass_fields__))
        self.cpu = Cpu(
            a55=self.boolean(cpu["a55"], "cpu.a55"),
            a76_core2=self.boolean(cpu["a76_core2"], "cpu.a76_core2"),
            a76_core3=self.boolean(cpu["a76_core3"], "cpu.a76_core3"),
            boot_core=self.choice(cpu["boot_core"], "cpu.boot_core", (0, 2)),
            l3_cache_mb=self.choice(cpu["l3_cache_mb"], "cpu.l3_cache_mb", (0, 1, 2)),
            mpu_frequency_hz=self.natural(cpu["mpu_frequency_hz"], "cpu.mpu_frequency_hz"),
        )
        if not (self.cpu.a55 or self.cpu.a76_core2 or self.cpu.a76_core3):
            self.fail("cpu: at least one core must be powered")
        if self.cpu.boot_core == 0 and not self.cpu.a55:
            self.fail("cpu.boot_core: core 0 is not powered")
        if self.cpu.boot_core == 2 and not self.cpu.a76_core2:
            self.fail("cpu.boot_core: core 2 is not powered")

        self.peripherals = frozenset(self.names(top["peripherals"], "peripherals",
                                                self.PERIPHERALS))
        self.use_fpga = frozenset(self.names(top.get("use_fpga", []), "use_fpga",
                                             self.USE_FPGA))
        self.watchdog_reset = self.choice(top["watchdog_reset"], "watchdog_reset",
                                          tuple(self.WATCHDOG_RESETS))

        self.emif_topology = None
        if "emif" in top:
            emif = self.mapping(top["emif"], "emif")
            self.keys(emif, "emif", required={"topology"})
            self.emif_topology = self.choice(emif["topology"], "emif.topology",
                                             self.EMIF_TOPOLOGIES)

        self.bridges: dict[str, Bridge] = {}
        bridges = self.mapping(top.get("bridges", {}), "bridges")
        self.keys(bridges, "bridges", allowed=set(self.BRIDGES))
        for name, value in bridges.items():
            widths, max_address = self.BRIDGES[name]
            b = self.mapping(value, f"bridges.{name}")
            self.keys(b, f"bridges.{name}", required={"data_width", "address_width"})
            data_width = self.choice(b["data_width"], f"bridges.{name}.data_width", widths)
            address_width = self.natural(b["address_width"], f"bridges.{name}.address_width")
            if not self.MIN_ADDRESS_WIDTH <= address_width <= max_address:
                self.fail(f"bridges.{name}.address_width: must be from "
                          f"{self.MIN_ADDRESS_WIDTH} to {max_address}")
            self.bridges[name] = Bridge(data_width, address_width)
        if "f2sdram" in self.bridges and self.emif_topology is None:
            self.fail("bridges.f2sdram: needs the HPS EMIF (emif)")

        pins = self.mapping(top["pins"], "pins")
        if set(pins) != set(range(self.PIN_COUNT)):
            missing = sorted(set(range(self.PIN_COUNT)) - set(pins))
            extra = sorted(set(pins) - set(range(self.PIN_COUNT)), key=str)
            self.fail(f"pins: every pin 0 to {self.PIN_COUNT - 1} must be given"
                      + (f", missing {missing}" if missing else "")
                      + (f", unknown {extra}" if extra else ""))
        self.pins: list[Pin] = []
        for index in range(self.PIN_COUNT):
            where = f"pins.{index}"
            p = self.mapping(pins[index], where)
            self.keys(p, where, required={"select", "mode"},
                      allowed={"select", "mode", "input_delay", "output_delay"})
            self.pins.append(Pin(
                select=self.natural(p["select"], f"{where}.select", 15),
                mode=self.choice(p["mode"], f"{where}.mode", self.PIN_MODES),
                input_delay=self.natural(p.get("input_delay", 0), f"{where}.input_delay"),
                output_delay=self.natural(p.get("output_delay", 0), f"{where}.output_delay"),
            ))

        clocks = self.mapping(top["clock_manager"], "clock_manager")
        self.keys(clocks, "clock_manager", required=set(self.CLOCK_MANAGER))
        self.clock_manager = {k: self.natural(clocks[k], f"clock_manager.{k}")
                              for k in self.CLOCK_MANAGER}

    @classmethod
    def load(cls, path: Path) -> HpsConfig:
        with open(path) as f:
            return cls(yaml.safe_load(f), str(path))

    @property
    def mpfe_used(self) -> bool:
        """Whether the MPFE is needed: it carries f2h, f2sdram and the HPS
        path to its EMIF"""
        return ("f2h" in self.bridges or "f2sdram" in self.bridges
                or self.emif_topology is not None)

    def fail(self, message: str):
        raise HpsConfigError(f"{self.origin}: {message}")

    def mapping(self, value, where: str) -> dict:
        if not isinstance(value, dict):
            self.fail(f"{where}: expected a mapping")
        return value

    def keys(self, value: dict, where: str, required: set = frozenset(), allowed: set = None):
        allowed = required if allowed is None else allowed
        missing = sorted(required - set(value), key=str)
        unknown = sorted(set(value) - allowed, key=str)
        if missing:
            self.fail(f"{where}: missing {', '.join(map(str, missing))}")
        if unknown:
            self.fail(f"{where}: unknown {', '.join(map(str, unknown))}")

    def boolean(self, value, where: str) -> bool:
        if not isinstance(value, bool):
            self.fail(f"{where}: expected a boolean")
        return value

    def natural(self, value, where: str, maximum: int = None) -> int:
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            self.fail(f"{where}: expected a natural")
        if maximum is not None and value > maximum:
            self.fail(f"{where}: must be {maximum} or less")
        return value

    def choice(self, value, where: str, choices: tuple):
        if isinstance(value, bool) or value not in choices:
            self.fail(f"{where}: must be one of {', '.join(map(str, choices))}")
        return value

    def names(self, value, where: str, choices: tuple) -> list:
        if not isinstance(value, list):
            self.fail(f"{where}: expected a list")
        for v in value:
            self.choice(v, where, choices)
        return value
