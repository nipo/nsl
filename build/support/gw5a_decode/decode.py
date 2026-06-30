#!/usr/bin/env python3.13
"""Decode GTR12_QUADB primitive semantics by diffing Gowin IPgen outputs.

For each project subdirectory containing a valid serdes.v (Gowin
wizard output) and serdes.csr (bitstream-time register pokes), parse
the GTR12_QUADB instantiation port map and the CSR write sequence,
then emit:

* gtr_ports.csv: one row per primitive port, one column per config,
  cell = the normalised driving expression (constants folded).
* gtr_ports.md: human-readable summary, splitting ports into
  "constant across all configs" (wizard-baked defaults) and "varies"
  (config-dependent — these are what the wrapper has to drive).
* csr_writes.csv: one row per CSR address, columns per config,
  cell = the final value written (sequence flattened).
* csr_writes.md: human-readable summary, same split.

Configuration directories with no serdes.v are wizard-stub failures
and are skipped silently.
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass, field
from pathlib import Path


GTR_INST_RE = re.compile(
    r"GTR12_QUADB\s+\w+\s*\(\s*(?P<body>.*?)\s*\)\s*;",
    re.DOTALL,
)
PORT_RE = re.compile(r"\.(?P<name>\w+)\s*\(\s*(?P<expr>[^()]*(?:\([^)]*\)[^()]*)*)\s*\)")
CSR_LINE_RE = re.compile(
    r"upar_write_driver\(\s*0x(?P<addr>[0-9A-Fa-f]+)\s*,\s*0x(?P<val>[0-9A-Fa-f]+)\s*\)"
)
WS_RE = re.compile(r"\s+")


class Expr:
    """Normalises a port-connection expression into a comparable form."""

    @staticmethod
    def normalise(expr: str) -> str:
        e = WS_RE.sub("", expr)
        if e == "gw_gnd":
            return "0"
        if e == "gw_vcc":
            return "1"
        if e.startswith("{") and e.endswith("}"):
            elems = [x.strip() for x in e[1:-1].split(",")]
            if elems and all(x == "gw_gnd" for x in elems):
                return f"0:{len(elems)}"
            if elems and all(x == "gw_vcc" for x in elems):
                return f"1:{len(elems)}"
            if elems and all(x in ("gw_gnd", "gw_vcc") for x in elems):
                bits = "".join("1" if x == "gw_vcc" else "0" for x in elems)
                return f"b{bits}"
        return e


@dataclass
class Config:
    name: str
    directory: Path
    ports: dict[str, str] = field(default_factory=dict)
    csr_final: dict[int, int] = field(default_factory=dict)
    csr_sequence: list[tuple[int, int]] = field(default_factory=list)

    def parse(self) -> None:
        serdes_v = self.directory / "serdes.v"
        csr = self.directory / "serdes.csr"
        if serdes_v.is_file():
            self.ports = self.parse_ports(serdes_v.read_text())
        if csr.is_file():
            self.parse_csr(csr.read_text())

    @staticmethod
    def parse_ports(source: str) -> dict[str, str]:
        match = GTR_INST_RE.search(source)
        if not match:
            return {}
        body = match.group("body")
        out: dict[str, str] = {}
        for pm in PORT_RE.finditer(body):
            out[pm.group("name")] = Expr.normalise(pm.group("expr"))
        return out

    def parse_csr(self, source: str) -> None:
        for line in CSR_LINE_RE.finditer(source):
            addr = int(line.group("addr"), 16)
            val = int(line.group("val"), 16)
            self.csr_sequence.append((addr, val))
            self.csr_final[addr] = val


def discover(root: Path) -> list[Config]:
    configs: list[Config] = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        if not (child / "serdes.v").is_file():
            continue
        cfg = Config(name=child.name, directory=child)
        cfg.parse()
        if not cfg.ports:
            continue
        configs.append(cfg)
    return configs


def emit_port_table(configs: list[Config], out: Path) -> None:
    names = [c.name for c in configs]
    all_ports = sorted({p for c in configs for p in c.ports})
    with out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["port", "varies"] + names)
        for port in all_ports:
            values = [c.ports.get(port, "") for c in configs]
            varies = len({v for v in values if v}) > 1
            w.writerow([port, "yes" if varies else "no"] + values)


def group_by_value(values: dict[str, str]) -> list[tuple[str, list[str]]]:
    inv: dict[str, list[str]] = {}
    for cfg, val in values.items():
        inv.setdefault(val, []).append(cfg)
    return sorted(inv.items())


def emit_port_summary(configs: list[Config], out: Path) -> None:
    all_ports = sorted({p for c in configs for p in c.ports})
    constants: dict[str, str] = {}
    varying: list[tuple[str, dict[str, str]]] = []
    for port in all_ports:
        per_config = {c.name: c.ports.get(port, "<absent>") for c in configs}
        unique = {v for v in per_config.values() if v != "<absent>"}
        if len(unique) == 1 and "<absent>" not in per_config.values():
            constants[port] = next(iter(unique))
        else:
            varying.append((port, per_config))

    with out.open("w") as f:
        f.write("================================\n")
        f.write("GTR12_QUADB port connection diff\n")
        f.write("================================\n\n")
        f.write(f":Configurations sampled: {len(configs)}\n\n")
        for c in configs:
            f.write(f"- ``{c.name}``\n")
        f.write("\n")
        f.write(f".. contents::\n   :local:\n\n")

        f.write("Notation\n========\n\n")
        f.write("- ``0`` / ``1``: single-bit tie to ``gw_gnd`` / ``gw_vcc``.\n")
        f.write("- ``0:N`` / ``1:N``: N-bit aggregate of ``gw_gnd`` / ``gw_vcc``.\n")
        f.write("- ``b<bits>``: mixed-constant aggregate, MSB-first.\n")
        f.write("- Anything else: the literal driving expression as it appears\n")
        f.write("  in ``serdes.v`` (usually a wire name like ``q0_fabric_ln0_rstn_i``).\n\n")

        f.write(f"Constant ports ({len(constants)})\n")
        f.write("=" * (len(f"Constant ports ({len(constants)})")) + "\n\n")
        f.write("Wizard-baked defaults: no sampled configuration changes these.\n")
        f.write("The VHDL backend can tie them to these values safely.\n\n")
        for port in sorted(constants):
            f.write(f"- ``{port}`` <- ``{constants[port]}``\n")
        f.write("\n")

        f.write(f"Varying ports ({len(varying)})\n")
        f.write("=" * (len(f"Varying ports ({len(varying)})")) + "\n\n")
        for port, per_config in varying:
            f.write(f"``{port}``\n")
            f.write("-" * (len(port) + 4) + "\n\n")
            for val, cfgs in group_by_value(per_config):
                f.write(f"- ``{val}``:\n")
                for c in cfgs:
                    f.write(f"\n  - ``{c}``\n")
            f.write("\n")


def emit_csr_table(configs: list[Config], out: Path) -> None:
    names = [c.name for c in configs]
    all_addrs = sorted({a for c in configs for a in c.csr_final})
    with out.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["address", "varies"] + names)
        for addr in all_addrs:
            values = [c.csr_final.get(addr) for c in configs]
            unique = {v for v in values if v is not None}
            varies = len(unique) > 1
            row = [f"0x{addr:08x}", "yes" if varies else "no"]
            row += [f"0x{v:08x}" if v is not None else "" for v in values]
            w.writerow(row)


def emit_csr_summary(configs: list[Config], out: Path) -> None:
    all_addrs = sorted({a for c in configs for a in c.csr_final})
    constants: dict[int, int] = {}
    varying: list[int] = []
    for addr in all_addrs:
        per_config = {c.name: c.csr_final.get(addr) for c in configs}
        unique = {v for v in per_config.values() if v is not None}
        absent_any = any(v is None for v in per_config.values())
        if len(unique) == 1 and not absent_any:
            constants[addr] = next(iter(unique))
        else:
            varying.append(addr)

    with out.open("w") as f:
        title = "CSR write diff: summary"
        f.write("=" * len(title) + "\n")
        f.write(title + "\n")
        f.write("=" * len(title) + "\n\n")
        f.write(f":Configurations sampled: {len(configs)}\n")
        f.write(f":Distinct CSR addresses written: {len(all_addrs)}\n")
        f.write(f":Constant across all configs: {len(constants)}\n")
        f.write(f":Varying across configs: {len(varying)}\n\n")
        f.write("The full per-address per-config table is in\n")
        f.write("``csr_writes.csv``. This summary lists only the addresses\n")
        f.write("that *vary* across configurations; their values are where\n")
        f.write("refclk routing, line rate, encoding, polarity and analog\n")
        f.write("tuning actually live.\n\n")
        f.write("Varying addresses\n")
        f.write("=================\n\n")
        for addr in varying:
            f.write(f"- ``0x{addr:08x}``\n")
        f.write("\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--src", type=Path, required=True,
                    help="Directory containing IPgen project subdirectories")
    ap.add_argument("--out", type=Path, required=True,
                    help="Output directory for tables and notes")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    configs = discover(args.src)
    if not configs:
        print(f"No valid configs found under {args.src}")
        return

    print(f"Decoded {len(configs)} configurations.")
    for c in configs:
        print(f"  - {c.name}: {len(c.ports)} ports, {len(c.csr_final)} csr writes")

    emit_port_table(configs, args.out / "gtr_ports.csv")
    emit_port_summary(configs, args.out / "gtr_ports.rst")
    emit_csr_table(configs, args.out / "csr_writes.csv")
    emit_csr_summary(configs, args.out / "csr_writes.rst")
    print(f"Wrote: gtr_ports.csv, gtr_ports.rst, csr_writes.csv, csr_writes.rst")


if __name__ == "__main__":
    main()
