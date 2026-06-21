#!/usr/bin/env python3.13
"""
Generate project.gbs.yaml for every test enrolled in tests/Makefile and
emit a top-level tests/suite.gbs.yaml describing the GBS test suite.

Inputs per leaf testbench:
- <leaf>/Makefile: provides `top = work.<topcell>`
- <leaf>/src/Makefile: provides `vhdl-sources +=` and `deps +=` lines
- <leaf>/src/*.vhd: scanned for nsl_simulation.control to gate success_regex

Idempotent: re-running overwrites generated files only.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TESTS_DIR = REPO_ROOT / "tests"

TOP_RE = re.compile(r"^top\s*=\s*work\.(\S+)\s*$", re.MULTILINE)
TB_RE = re.compile(r"^tb\s*\+=\s*(\S+)\s*$", re.MULTILINE)
SRC_RE = re.compile(r"^vhdl-sources\s*\+=\s*(\S+)\s*$", re.MULTILINE)
DEP_RE = re.compile(r"^deps\s*\+=\s*(\S+)\s*$", re.MULTILINE)
class TestbenchLeaf:
    def __init__(self, rel_path: str, leaf_dir: Path) -> None:
        self.rel_path = rel_path
        self.leaf_dir = leaf_dir

    @property
    def name(self) -> str:
        return self.rel_path.replace("/", "_")

    @property
    def project_file(self) -> Path:
        return self.leaf_dir / "project.gbs.yaml"

    def parse(self) -> dict:
        leaf_mk = (self.leaf_dir / "Makefile").read_text()
        src_mk = (self.leaf_dir / "src" / "Makefile").read_text()
        top_match = TOP_RE.search(leaf_mk)
        if not top_match:
            raise ValueError(f"{self.rel_path}: no `top = work.X` in Makefile")
        sources = SRC_RE.findall(src_mk)
        if not sources:
            raise ValueError(f"{self.rel_path}: no vhdl-sources in src/Makefile")
        deps = DEP_RE.findall(src_mk)
        return dict(topcell=top_match.group(1), sources=sources, deps=deps)

    def uses_control(self, deps: list[str]) -> bool:
        return any(d in ("nsl_simulation.control", "nsl_simulation.driver")
                   for d in deps)

    def render(self) -> str:
        info = self.parse()
        lines = [f"name: {self.name}", "", "root:", "  name: top", "  deps:"]
        for dep in info["deps"]:
            lines.append(f"    - {dep}")
        lines.append("  sources:")
        lines.append("    - file_type: vhdl")
        lines.append("      files:")
        for s in info["sources"]:
            lines.append(f"        - src/{s}")
        lines.append("")
        lines.append("output:")
        lines.append("  - name: simulation")
        lines.append(f"    topcell: {info['topcell']}")
        if self.uses_control(info["deps"]):
            lines.append("    backend_config:")
            lines.append("      gbs.builtin.ghdl:")
            lines.append(
                '        success_regex: "Terminating with error level: 0"'
            )
        lines.append("    outputs:")
        lines.append("      - type: simulation-log")
        lines.append("        path: simulation.log")
        lines.append("")
        return "\n".join(lines)


class Suite:
    def __init__(self, leaves: list[TestbenchLeaf]) -> None:
        self.leaves = sorted(leaves, key=lambda l: l.rel_path)

    def render(self) -> str:
        lines = [
            "name: nsl-tests",
            "description: NSL test suite",
            "",
            "settings:",
            "  max_parallel_projects: 4",
            "  stop_on_failure: false",
            "  output:",
            "    junit_xml: test-results/junit.xml",
            "    summary_json: test-results/summary.json",
            "    log_dir: test-results/logs",
            "    save_logs: true",
            "",
            "projects:",
        ]
        for leaf in self.leaves:
            lines.append(f"  - name: {leaf.name}")
            lines.append(f"    path: {leaf.rel_path}")
            lines.append(f"    tags: [ghdl, simulation]")
        lines.append("")
        return "\n".join(lines)


class Enroller:
    """Discover leaves transitively reachable from tests/Makefile tb += entries."""

    def __init__(self, tests_dir: Path) -> None:
        self.tests_dir = tests_dir

    def discover(self) -> list[TestbenchLeaf]:
        root_mk = (self.tests_dir / "Makefile").read_text()
        leaves: list[TestbenchLeaf] = []
        seen: set[str] = set()
        for entry in TB_RE.findall(root_mk):
            self.__expand(entry, leaves, seen)
        return leaves

    def __record(self, leaf: TestbenchLeaf, leaves: list[TestbenchLeaf],
                 seen: set[str]) -> None:
        if leaf.rel_path in seen:
            return
        seen.add(leaf.rel_path)
        leaves.append(leaf)

    def __expand(self, rel_path: str, leaves: list[TestbenchLeaf],
                 seen: set[str]) -> None:
        leaf_dir = self.tests_dir / rel_path
        leaf_mk = leaf_dir / "Makefile"
        if not leaf_mk.exists():
            raise ValueError(f"tb += {rel_path}: {leaf_mk} missing")
        body = leaf_mk.read_text()
        if TOP_RE.search(body):
            self.__record(TestbenchLeaf(rel_path, leaf_dir), leaves, seen)
            return
        sub_entries = TB_RE.findall(body)
        if not sub_entries:
            print(f"warning: tb += {rel_path}: aggregator with no enrolled leaves; skipping",
                  file=sys.stderr)
            return
        for sub in sub_entries:
            self.__expand(f"{rel_path}/{sub}", leaves, seen)


def main() -> int:
    leaves = Enroller(TESTS_DIR).discover()
    skipped: list[tuple[str, str]] = []
    written = 0
    for leaf in leaves:
        try:
            content = leaf.render()
        except Exception as e:
            skipped.append((leaf.rel_path, str(e)))
            continue
        leaf.project_file.write_text(content)
        written += 1
    suite_path = TESTS_DIR / "suite.gbs.yaml"
    kept = [l for l in leaves if (l.rel_path, "") not in skipped]
    # Reuse skipped list to filter
    skipped_set = {p for p, _ in skipped}
    kept = [l for l in leaves if l.rel_path not in skipped_set]
    suite_path.write_text(Suite(kept).render())
    print(f"Wrote {written} project.gbs.yaml files")
    print(f"Wrote {suite_path}")
    if skipped:
        print("Skipped:")
        for p, err in skipped:
            print(f"  - {p}: {err}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
