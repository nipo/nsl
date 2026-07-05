"""NSL Plugin for GBS

Provides:
- tree: NSL tree repository loader
- cdc: CDC constraint generation dispatchers for Gowin and ISE
- filter_vars: legacy variable aliases for the NSL Makefile tree

The CDC dispatchers activate when a netlist is generated (gowin-netlist or ise-netlist).
"""

import sys
from pathlib import Path
from typing import Any
from gbs.base import *

__all__ = ['gbs_register']


class NslPlugin(BasePlugin):
    """NSL plugin providing repository parser, CDC dispatcher and
    legacy filter-variable aliases."""

    __LATTICE_FAMILY_HWDEP = {
        "ice40": "lattice-ice40",
        "ecp5": "lattice-ecp5",
        "machxo2": "lattice-machxo2",
        "nexus": "lattice-nexus",
        "certus": "lattice-certus",
    }

    __GHDL_FLAVOR_RE = None

    def __init__(self):
        super().__init__(
            name="gbs.plugin.nsl",
            description="NSL tree repository parser and CDC constraint generator",
            version="1.0.0"
        )

    def generic_dispatchers(self, context):
        """Return NSL CDC dispatchers"""
        from pathlib import Path
        from .cdc import CdcGowinDispatcher
        from .cdc import CdcVivadoDispatcher
        return [
            CdcGowinDispatcher(context),
            CdcVivadoDispatcher(context),
        ]

    def enumerate_backends(self):
        """Return NSL CDC backends"""
        from .cdc import CdcIseBackend
        return [CdcIseBackend()]

    def enumerate_repository_parsers(self):
        """Return NSL tree repository parser class"""
        from .repository import NSLTreeLoader
        return {"nsl-tree": NSLTreeLoader}

    def transform_filter_vars(self, filter_vars: dict[str, Any]) -> dict[str, Any]:
        """Synthesize legacy NSL Makefile variables from the canonical set.

        NSL's tree of Makefiles predates the canonical GBS filter-variable
        spec and matches on names like ``target-usage``, ``hwdep``,
        ``target_part``, ``target_speed``, ``ghdl-flavor``, ``VHDL_VERSION``
        and (occasionally) ``compiler``/``tool``. This transform derives
        those from the canonical set so NSL Makefiles keep working.
        """
        legacy: dict[str, Any] = {}

        purpose = filter_vars.get("purpose")
        if purpose is not None:
            legacy["target-usage"] = purpose

        part = filter_vars.get("part")
        if part is not None:
            legacy["target_part"] = part

        family = filter_vars.get("family")
        if family is not None:
            legacy["target_part_name"] = family

        speed = filter_vars.get("speed")
        if speed is not None:
            legacy["target_speed"] = speed

        vhdl_std = filter_vars.get("vhdl_std")
        if vhdl_std is not None:
            legacy["VHDL_VERSION"] = vhdl_std

        # tool / compiler: pick the first of synthesis_engine,
        # simulation_engine, vhdl_frontend that is set, and strip any
        # ghdl_<flavor> suffix down to just "ghdl".
        engine = (filter_vars.get("synthesis_engine")
                  or filter_vars.get("simulation_engine")
                  or filter_vars.get("vhdl_frontend"))
        if engine is not None:
            family_engine = self.__engine_family(engine)
            legacy["tool"] = family_engine
            legacy["compiler"] = family_engine

        # GHDL flavour: any occurrence of ghdl_<flavor> in a stage
        # variable exposes the flavor as legacy ghdl-flavor.
        flavor = self.__ghdl_flavor(filter_vars)
        if flavor is not None:
            legacy["ghdl-flavor"] = flavor

        # hwdep: vendor + (family for lattice) — or "simulation" when
        # no vendor is set.
        vendor = filter_vars.get("vendor")
        if vendor is None:
            legacy["hwdep"] = "simulation"
        elif vendor == "lattice":
            legacy["hwdep"] = self.__LATTICE_FAMILY_HWDEP.get(
                family, "lattice"
            )
        else:
            legacy["hwdep"] = vendor

        return legacy

    @staticmethod
    def __engine_family(engine: str) -> str:
        """Strip a trailing _flavor from a stage-engine value.

        ``ghdl_llvm`` -> ``ghdl``. Anything without an underscore
        passes through unchanged.
        """
        if "_" in engine:
            head = engine.split("_", 1)[0]
            # Keep names like gowin_synth intact — only strip when the
            # tail is a known GHDL flavor.
            tail = engine.split("_", 1)[1]
            if head == "ghdl" and tail in ("mcode", "llvm", "gcc", "jit"):
                return head
        return engine

    @staticmethod
    def __ghdl_flavor(filter_vars: dict[str, Any]) -> str | None:
        for key in ("simulation_engine", "vhdl_frontend"):
            value = filter_vars.get(key)
            if not isinstance(value, str):
                continue
            if not value.startswith("ghdl_"):
                continue
            flavor = value[len("ghdl_"):]
            if flavor in ("mcode", "llvm", "gcc", "jit"):
                return flavor
        return None


def gbs_register():
    """Plugin registration function

    Called by the plugin system during discovery.
    Must return one or more Plugin instances.
    """
    return NslPlugin()
