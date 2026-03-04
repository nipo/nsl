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
"""

from pathlib import Path
import re
from typing import Any
import sys

from gbs.base import *
from gbs.build.context import BuildContext
from gbs.build.task import Task, ResourceTypology


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

        # Generate constraints
        constraints = []

        # NSL TIG patterns and their corresponding SDC constraints
        # Each pattern is (regex_pattern, pin_type, pin_name)
        patterns = [
            (r'tig_reg_clr', 'to', 'CLEAR'),
            (r'tig_reg_pre', 'to', 'PRE'),
            (r'tig_reg_q', 'from', 'O'),
            (r'tig_reg_q', 'from', 'Q'),
            (r'tig_static_reg', 'from', 'Q'),
            (r'tig_static_reg', 'to', 'D'),
            (r'cross_region_reg', 'to', 'D'),
            (r'async_net', 'to', 'D'),
            (r'async_net', 'from', 'Q'),
        ]

        constraints.append("# NSL CDC Constraints")
        constraints.append(f"# Generated from {netlist_file.name}")
        constraints.append("")

        # Check each pattern and generate constraints
        for pattern, direction, pin_name in patterns:
            if re.search(pattern, netlist_content):
                constraint = f"set_false_path -{direction} [get_pins {{*{pattern}*/{pin_name}}}]"
                constraints.append(constraint)
                self.debug(f"Added constraint: {constraint}")

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
