#!/usr/bin/env python3.13
"""Audit a VHDL backend's GTR12_QUADB port map against the decoded
wizard reference.

Reads our transceiver_group_gw5a.vhd, extracts the GTR12_QUADB port
map, and cross-checks each port against gtr_ports.csv. Reports:

* mismatches on constant tie-offs (wizard always ties to X, we tie
  to Y);
* ports the wizard always wires to a named internal signal but we
  leave open or tied to a constant (potential missing functionality);
* ports the wizard varies across configurations but we tie to a
  constant (potential missing per-lane / runtime path);
* ports the wizard *never* connects to anything we don't already
  match — i.e. our map is correct against the sample.

This audit is necessarily relative to the sampled configurations: a
port the wizard ties to ground in every sampled config might still
be runtime-driven in a config we did not generate.
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass, field
from pathlib import Path


COMPONENT_RE = re.compile(
    r"component\s+GTR12_QUADB\s+is\s+port\s*\((.*?)\)\s*;\s*end\s+component\s*;",
    re.DOTALL | re.IGNORECASE,
)
PORT_DECL_RE = re.compile(
    r"\b(\w+)\s*:\s*(in|out)\s+(\w+(?:\s*\([^)]*\))?)",
    re.IGNORECASE,
)
INST_RE = re.compile(
    r":\s*GTR12_QUADB\s+port\s+map\s*\((?P<body>.*?)\)\s*;",
    re.DOTALL | re.IGNORECASE,
)
ASSOC_RE = re.compile(
    r"(?P<port>\w+)\s*=>\s*(?P<actual>[^,]+?)\s*(?=,\s*\w+\s*=>|$)",
    re.DOTALL,
)
WS_RE = re.compile(r"\s+")


@dataclass
class PortDecl:
    name: str
    direction: str  # "in" or "out"
    vhd_type: str


@dataclass
class Reference:
    """Wizard reference for one primitive port."""
    name: str
    varies: bool
    values: list[str]  # per-config

    @property
    def constant_value(self) -> str | None:
        if self.varies:
            return None
        non_empty = [v for v in self.values if v]
        if not non_empty:
            return None
        return non_empty[0]


@dataclass
class Audit:
    declared_ports: dict[str, PortDecl] = field(default_factory=dict)
    actuals: dict[str, str] = field(default_factory=dict)
    reference: dict[str, Reference] = field(default_factory=dict)


def normalise_actual(expr: str) -> str:
    """Map our VHDL port-map values into the same vocabulary as the
    decoded reference: '0', '1', '0:N', '1:N', or the literal
    identifier / open."""
    e = expr.strip()
    if e.lower() == "open":
        return "open"
    if e == "gw_gnd" or e == "'0'":
        return "0"
    if e == "gw_vcc" or e == "'1'":
        return "1"
    # "000" / "0000" literal bit strings
    m = re.fullmatch(r'"([01]+)"', e)
    if m:
        bits = m.group(1)
        if set(bits) == {"0"}:
            return f"0:{len(bits)}"
        if set(bits) == {"1"}:
            return f"1:{len(bits)}"
        return f"b{bits}"
    # (others => '0') -> need declared port type to know width
    m = re.fullmatch(r"\(others\s*=>\s*'([01])'\)", e, re.IGNORECASE)
    if m:
        return f"others:{m.group(1)}"
    return e


def parse_component(vhd: str) -> dict[str, PortDecl]:
    m = COMPONENT_RE.search(vhd)
    if not m:
        return {}
    body = m.group(1)
    ports: dict[str, PortDecl] = {}
    for decl in re.finditer(
        r"(\w+)\s*:\s*(in|out)\s+([^;]+?)(?=\s*;|$)",
        body, re.IGNORECASE | re.DOTALL,
    ):
        name = decl.group(1)
        direction = decl.group(2).lower()
        vhd_type = WS_RE.sub(" ", decl.group(3)).strip()
        if name.lower() == "port":
            continue
        ports[name] = PortDecl(name=name, direction=direction, vhd_type=vhd_type)
    return ports


def parse_instantiation(vhd: str) -> dict[str, str]:
    m = INST_RE.search(vhd)
    if not m:
        return {}
    body = m.group("body")
    actuals: dict[str, str] = {}
    # Split on top-level commas; respect parenthesis depth so
    # "(others => '0')" stays intact.
    items = split_top_level(body)
    for item in items:
        if "=>" not in item:
            continue
        port, actual = item.split("=>", 1)
        actuals[port.strip()] = actual.strip()
    return actuals


def split_top_level(body: str) -> list[str]:
    items: list[str] = []
    depth = 0
    cur = []
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            items.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if cur:
        items.append("".join(cur))
    return [i.strip() for i in items if i.strip()]


def load_reference(csv_path: Path) -> dict[str, Reference]:
    refs: dict[str, Reference] = {}
    with csv_path.open() as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            port = row[0]
            varies = row[1] == "yes"
            values = row[2:]
            refs[port] = Reference(name=port, varies=varies, values=values)
    return refs


def width_from_type(vhd_type: str) -> int | None:
    """Extract vector width from a VHDL type expression."""
    m = re.search(r"\(\s*(\d+)\s+downto\s+(\d+)\s*\)", vhd_type)
    if m:
        return int(m.group(1)) - int(m.group(2)) + 1
    m = re.search(r"\(\s*(\d+)\s+to\s+(\d+)\s*\)", vhd_type)
    if m:
        return int(m.group(2)) - int(m.group(1)) + 1
    return None


EXPECTED_DIFFERENT = {
    # Differential pad ports: our entity exposes them as I/O; the wizard
    # internalises the pad routing through the synthesis tool and so
    # ties the fabric-side endpoint to ground.
    "LN0_TXM_O", "LN0_TXP_O", "LN1_TXM_O", "LN1_TXP_O",
    "LN2_TXM_O", "LN2_TXP_O", "LN3_TXM_O", "LN3_TXP_O",
    "LN0_RXM_I", "LN0_RXP_I", "LN1_RXM_I", "LN1_RXP_I",
    "LN2_RXM_I", "LN2_RXP_I", "LN3_RXM_I", "LN3_RXP_I",
    "REFCLKP0_I", "REFCLKM0_I", "REFCLKP1_I", "REFCLKM1_I",
    # Adapter-controllable sideband inputs the wizard never drives in
    # the sampled configurations but our backend exposes for adapter
    # flexibility (manual word alignment, channel-bond master role,
    # per-lane runtime control). Tied to 0 by adapters that don't need
    # them.
    "LANE0_ALIGN_TRIGGER", "LANE1_ALIGN_TRIGGER",
    "LANE2_ALIGN_TRIGGER", "LANE3_ALIGN_TRIGGER",
    "LANE1_CHBOND_START", "LANE2_CHBOND_START", "LANE3_CHBOND_START",
    "FABRIC_LN0_CTRL_I", "FABRIC_LN1_CTRL_I",
    "FABRIC_LN2_CTRL_I", "FABRIC_LN3_CTRL_I",
    "FABRIC_LN0_CTRL_I_H", "FABRIC_LN1_CTRL_I_H",
    "FABRIC_LN2_CTRL_I_H", "FABRIC_LN3_CTRL_I_H",
    "LANE0_FABRIC_C2I_CLK", "LANE1_FABRIC_C2I_CLK",
    "LANE2_FABRIC_C2I_CLK", "LANE3_FABRIC_C2I_CLK",
}


def compare(audit: Audit) -> tuple[list[str], list[str], list[str], list[str]]:
    """Return (mismatches, exposed_open, suspicious_open, ok)."""
    mismatches: list[str] = []
    exposed_open: list[str] = []
    suspicious_open: list[str] = []
    ok_count = 0

    for port_name, ref in audit.reference.items():
        if port_name in EXPECTED_DIFFERENT:
            ok_count += 1
            continue
        actual = audit.actuals.get(port_name)
        decl = audit.declared_ports.get(port_name)
        if actual is None:
            mismatches.append(f"{port_name}: not in VHDL port map")
            continue
        our = normalise_actual(actual)
        if our.startswith("others:"):
            bit = our.split(":")[1]
            width = width_from_type(decl.vhd_type) if decl else None
            if width is not None:
                our = f"{bit}:{width}"

        if ref.varies:
            if our in ("0", "1") or re.match(r"^[01]:\d+$", our):
                mismatches.append(
                    f"{port_name}: VARIES across wizard configs, but we tie to {our}"
                )
            else:
                ok_count += 1
            continue

        wizard = ref.constant_value
        if wizard is None:
            continue

        if our == "open":
            if decl and decl.direction == "out":
                if wizard.startswith("q0_") or wizard.startswith("ahb_"):
                    exposed_open.append(
                        f"{port_name}: open in VHDL, wizard wires to {wizard}"
                    )
                else:
                    ok_count += 1
                continue
            mismatches.append(
                f"{port_name}: VHDL says open on input port; wizard ties to {wizard}"
            )
            continue

        if wizard.startswith("q0_") or wizard.startswith("ahb_"):
            if decl and decl.direction == "out":
                if our != "open":
                    suspicious_open.append(
                        f"{port_name}: VHDL exposes as signal ({our}); "
                        f"wizard routes to internal wire {wizard} (probably fine, "
                        f"just confirms output is consumed)"
                    )
                    continue
            ok_count += 1
            continue

        if our == wizard:
            ok_count += 1
        else:
            mismatches.append(
                f"{port_name}: VHDL = {our}, wizard = {wizard}"
            )

    return mismatches, exposed_open, suspicious_open, [f"{ok_count} ports match"]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vhd", type=Path, required=True,
                    help="VHDL backend file (transceiver_group_gw5a.vhd)")
    ap.add_argument("--reference", type=Path, required=True,
                    help="Decoded reference CSV (gtr_ports.csv)")
    args = ap.parse_args()

    vhd = args.vhd.read_text()
    audit = Audit()
    audit.declared_ports = parse_component(vhd)
    audit.actuals = parse_instantiation(vhd)
    audit.reference = load_reference(args.reference)

    print(f"Component declares {len(audit.declared_ports)} ports.")
    print(f"Instantiation binds  {len(audit.actuals)} ports.")
    print(f"Reference covers     {len(audit.reference)} ports.\n")

    only_in_ref = set(audit.reference) - set(audit.actuals)
    only_in_vhd = set(audit.actuals) - set(audit.reference)
    if only_in_ref:
        print(f"-- {len(only_in_ref)} ports in reference but not in our port map:")
        for p in sorted(only_in_ref):
            print(f"   {p}")
        print()
    if only_in_vhd:
        print(f"-- {len(only_in_vhd)} ports in our port map but not in reference:")
        for p in sorted(only_in_vhd):
            print(f"   {p}")
        print()

    mismatches, exposed_open, suspicious_open, ok = compare(audit)
    print(f"== Mismatches ({len(mismatches)}) ==")
    for m in mismatches:
        print(f"  {m}")
    print()
    print(f"== Outputs we marked open that wizard wires ({len(exposed_open)}) ==")
    print("  (May indicate functionality not yet plumbed through to the adapter.)")
    for m in exposed_open:
        print(f"  {m}")
    print()
    print(f"== OK: {ok[0]} ==")


if __name__ == "__main__":
    main()
