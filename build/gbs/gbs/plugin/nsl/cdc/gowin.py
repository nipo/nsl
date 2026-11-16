"""NSL CDC Constraint Generator for Gowin

Generates SDC timing constraints for NSL timing-insensitive constructs.

NSL uses special naming patterns for signals that should be excluded from
timing analysis:
- tig_reg_clr: Registers with timing-ignored clear signals
- tig_reg_pre: Registers with timing-ignored preset signals
- tig_reg_q: Registers with timing-ignored outputs
- tig_static_reg: Static registers (constant after initialization)
- cross_region_reg: Clock domain crossing registers
- async_net: Asynchronous nets

This backend:
1. Runs after Gowin synthesis
2. Reads the generated netlist file
3. Searches for NSL TIG patterns
4. Generates set_false_path constraints
5. Adds the SDC file to the fileset for PnR

Gowin releases before 1.9.12 only accept wildcards within the last
hierarchy level of an object name: a leading `*` is a syntax error and a
`*` standing for hierarchy levels matches nothing. For those, and when
the suite version is unknown, constraints name every matching cell pin
with its full hierarchical path, as found in the netlist.
"""

from pathlib import Path
import re
from typing import Any
import sys

from gbs.base import *
from gbs.build.context import BuildContext
from gbs.build.task import Task, ResourceTypology

# Each pattern is (cell name pattern, set_false_path direction, cell pin)
NSL_PATTERNS = [
    ('tig_reg_clr', 'to', 'CLEAR'),
    ('tig_reg_pre', 'to', 'PRE'),
    ('tig_reg_q', 'from', 'O'),
    ('tig_reg_q', 'from', 'Q'),
    ('tig_static_reg', 'from', 'Q'),
    ('tig_static_reg', 'to', 'D'),
    ('cross_region_reg', 'to', 'D'),
    ('async_net', 'to', 'D'),
    ('async_net', 'from', 'Q'),
]

# First Gowin suite release known to resolve `*` across hierarchy levels
HIERARCHICAL_WILDCARD_VERSION = (1, 9, 12)


class GowinNetlist:
    """Instance hierarchy of a Gowin synthesis netlist (.vg)

    Only what constraint generation needs is retained: for each module,
    its instances with their cell type and connected pin names.
    """

    _ident = r'(?:\\\S+|[A-Za-z_][\w$]*)'
    _module_re = re.compile(rf'^module\s+(?P<name>{_ident})')
    _instance_re = re.compile(
        rf'^\s+(?P<type>{_ident})\s+(?P<name>{_ident})\s*\(\s*$')
    _pin_re = re.compile(r'^\s*\.(?P<pin>[A-Za-z_]\w*)\s*\(')

    def __init__(self, text: str):
        self.modules: dict[str, list[tuple[str, str, set[str]]]] = {}
        module = None
        instance = None
        for line in text.splitlines():
            match = self._module_re.match(line)
            if match:
                module = self.modules.setdefault(self._unescape(match["name"]), [])
                instance = None
                continue
            if line.startswith("endmodule"):
                module = None
                instance = None
                continue
            if module is None:
                continue
            match = self._instance_re.match(line)
            if match:
                instance = (self._unescape(match["type"]),
                            self._unescape(match["name"]), set())
                module.append(instance)
                continue
            if instance is not None:
                match = self._pin_re.match(line)
                if match:
                    instance[2].add(match["pin"])

    @staticmethod
    def _unescape(name: str) -> str:
        return name[1:] if name.startswith("\\") else name

    def top(self) -> str:
        """Name of the only module no other module instantiates"""
        used = {cell for instances in self.modules.values()
                for cell, _, _ in instances}
        tops = [name for name in self.modules if name not in used]
        if len(tops) != 1:
            raise ValueError(f"Cannot find netlist top module among {tops}")
        return tops[0]

    def leaf_cells(self, module: str | None = None, prefix: str = ""):
        """Yield (hierarchical path, cell type, pins) of every primitive"""
        for cell, name, pins in self.modules[module or self.top()]:
            path = f"{prefix}{name}"
            if cell in self.modules:
                yield from self.leaf_cells(cell, f"{path}/")
            else:
                yield path, cell, pins


def wildcard_constraints(netlist_content: str) -> list[str]:
    """Constraints matching NSL cells by name pattern"""
    constraints = []
    for pattern, direction, pin_name in NSL_PATTERNS:
        if re.search(pattern, netlist_content):
            constraints.append(
                f"set_false_path -{direction} [get_pins {{*{pattern}*/{pin_name}}}]")
    return constraints


def explicit_constraints(netlist_content: str) -> list[str]:
    """Constraints naming each NSL cell pin with its full path"""
    cells = list(GowinNetlist(netlist_content).leaf_cells())
    constraints = []
    for pattern, direction, pin_name in NSL_PATTERNS:
        for path, _, pins in cells:
            if pattern in path and pin_name in pins:
                constraints.append(
                    f"set_false_path -{direction} [get_pins {{{path}/{pin_name}}}]")
    return constraints


class CdcGowinConstraintTask(Task):
    """Generate NSL CDC constraints from Gowin netlist"""

    def __init__(
        self,
        dispatcher,
        inputs,
        outputs
    ):
        super().__init__(
            dispatcher,
            "nsl_gowin_cdc_constraints",
            inputs=inputs,
            outputs=outputs,
            description="Generate NSL CDC constraints"
        )

    async def work(self):
        """Generate SDC constraints by parsing netlist"""
        netlist, = self.inputs
        sdc, = self.outputs

        netlist_file = netlist.path
        sdc_file = sdc.path

        self.info(f"Generating NSL CDC constraints from {netlist_file}")

        netlist_content = netlist_file.read_text()

        version = netlist.metadata.get("gowin_version")
        if version is not None and tuple(version) >= HIERARCHICAL_WILDCARD_VERSION:
            body = wildcard_constraints(netlist_content)
        else:
            self.info(f"Gowin suite version {version} needs explicit cell paths")
            body = explicit_constraints(netlist_content)

        for constraint in body:
            self.debug(f"Added constraint: {constraint}")

        constraints = [
            "# NSL CDC Constraints",
            f"# Generated from {netlist_file.name}",
            "",
        ] + body

        # Write SDC file
        sdc_file.parent.mkdir(parents=True, exist_ok=True)
        sdc_file.write_text('\n'.join(constraints) + '\n')

        if len(constraints) > 3:  # More than just header comments
            self.info(f"Generated {len(constraints) - 3} NSL CDC constraints")
        else:
            self.info("No NSL TIG patterns found in netlist")


class CdcGowinDispatcher(BaseDispatcher):
    """NSL CDC constraint generation dispatcher

    Generates Gowin SDC constraints for NSL timing-insensitive constructs.

    Workflow:
    1. Waits for Gowin netlist to be generated
    2. Parses netlist for NSL TIG patterns
    3. Generates SDC file with set_false_path constraints
    4. Adds SDC file to fileset (Gowin backend picks it up dynamically)

    Priority: 650 (runs after Gowin synthesis at 600)
    """

    def __init__(
            self,
            context
    ):
        super().__init__(context, "nsl_gowin_cdc", tool_name = "nsl")
        self._constraint_task = None

    async def process(
        self,
    ):
        """Process netlist and generate CDC constraints"""

        # Only run once
        if self._constraint_task:
            return

        # Look for Gowin netlist
        netlist_files = list(self.context.filter_pending(file_type="gowin-netlist"))

        if not netlist_files:
            # No netlist yet - will be called again in next iteration
            return

        self.debug("Found Gowin netlist, generating NSL CDC constraints")

        # Use first netlist file
        netlist_resource = netlist_files[0]

        # Define output SDC file
        sdc_resource = self.context.get_resource(
            self.context.output_path / "nsl_cdc_constraints.sdc",
            file_type="gowin-sdc",
            typology=ResourceTypology.INTERMEDIATE,
            generated_by=self.name
        )

        # Create constraint generation task
        self._constraint_task = CdcGowinConstraintTask(
            dispatcher = self,
            inputs=[],
            outputs=[sdc_resource]
        )
        self._constraint_task.add_input(netlist_resource, consume = False)

        self.info(f"Scheduled NSL CDC constraint generation to {sdc_resource.path}")
