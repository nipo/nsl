"""NSL CDC Constraint Generator for Xilinx ISE

Generates UCF timing constraints for NSL timing-insensitive constructs.

NSL uses special naming patterns for signals that should be excluded from
timing analysis:
- tig_reg_clr: Registers with timing-ignored clear signals
- tig_reg_pre: Registers with timing-ignored preset signals
- tig_reg_d: Registers with timing-ignored data inputs
- tig_reg_q: Registers with timing-ignored outputs
- tig_static_reg_d: Static registers (constant after initialization)
- cross_region_reg_d: Clock domain crossing registers

This dispatcher:
1. Runs after ISE EDIF conversion
2. Reads the generated EDIF netlist
3. Reads NSL CCF (clock constraint file) for clock definitions
4. Searches for NSL TIG patterns in netlist
5. Generates UCF constraints with TIG timespecs and cross-domain paths
6. Adds the UCF file to the fileset for NGDBUILD
"""

from pathlib import Path
import re
from typing import Any
import sys

from gbs.base import *
from gbs.build.context import BuildContext
from gbs.build.task import Task, ResourceTypology


class CdcIseConstraintTask(Task):
    """Generate NSL CDC UCF constraints from ISE EDIF netlist and CCF files"""

    def __init__(
        self,
        dispatcher,
        inputs,
        outputs
    ):
        super().__init__(
            dispatcher,
            "nsl_cdc_ise_constraints",
            inputs=inputs,
            outputs=outputs,
            description="Generate NSL CDC UCF constraints for ISE"
        )

    async def work(self):
        """Generate UCF constraints by parsing netlist and CCF files"""

        # Get EDIF netlist from inputs
        edif_resources = self.inputs_of_type("ise-netlist")
        if not edif_resources:
            self.warning("No EDIF netlist found in inputs")
            return

        edif_file = edif_resources[0].path
        self.info(f"Generating NSL CDC constraints from {edif_file}")

        # Get CCF files from inputs
        ccf_resources = self.inputs_of_type("nsl-ccf")

        # Get output UCF file
        ucf_resources = self.outputs_of_type("xilinx-ucf")
        if not ucf_resources:
            self.error("No UCF output specified")
            return
        output_ucf_file = ucf_resources[0].path

        # Read EDIF netlist
        if not edif_file.exists():
            self.warning(f"EDIF file not found: {edif_file}")
            output_ucf_file.parent.mkdir(parents=True, exist_ok=True)
            output_ucf_file.write_text("")
            return

        edif_content = edif_file.read_text()

        # Check for TIG patterns in netlist
        patterns = self.check_tig_patterns(edif_content)

        # Parse all CCF files
        clocks = []
        for ccf_resource in ccf_resources:
            if ccf_resource.path.exists():
                ccf_content = ccf_resource.path.read_text()
                clocks.extend(self.parse_ccf(ccf_content))
                self.debug(f"Loaded clocks from {ccf_resource.path}")

        if not clocks:
            self.info("No clock definitions found in CCF files")
            output_ucf_file.parent.mkdir(parents=True, exist_ok=True)
            output_ucf_file.write_text("# No clock definitions\n")
            return

        # Generate constraints
        constraint_lines = self.generate_ucf_constraints(clocks, patterns)

        # Write UCF file
        output_ucf_file.parent.mkdir(parents=True, exist_ok=True)
        output_ucf_file.write_text('\n'.join(constraint_lines) + '\n')

        pattern_count = sum(1 for v in patterns.values() if v)
        self.info(
            f"Generated UCF with {len(clocks)} clocks, {pattern_count} TIG patterns, "
            f"{len(constraint_lines)} constraint lines"
        )


    @classmethod
    def sanitize_token(cls, name: str):
        """Convert a net name to a valid UCF token by replacing non-alphanumeric chars with underscore"""
        return re.sub(r'[^a-zA-Z0-9]', '_', name)

    @classmethod
    def parse_ccf(cls, ccf_content: str):
        """Parse CCF file content into list of (net_name, period) tuples

        CCF format: <net_name> <period_ns>
        Lines starting with # are comments, empty lines are ignored.
        """
        clocks = []
        for line in ccf_content.strip().split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                net_name = parts[0]
                try:
                    period = float(parts[1])
                    clocks.append((net_name, period))
                except ValueError:
                    continue
        return clocks

    @classmethod
    def check_tig_patterns(cls, edif_content: str):
        """Check which TIG patterns exist in the EDIF netlist"""
        return {
            'tig_clr': 'tig_reg_clr' in edif_content,
            'tig_pre': 'tig_reg_pre' in edif_content,
            'tig_d': 'tig_reg_d' in edif_content,
            'tig_q': 'tig_reg_q' in edif_content,
#            'tig_static_d': 'tig_static_reg_d' in edif_content,
            'ff_cross': 'cross_region_reg_d' in edif_content,
        }

    @classmethod
    def generate_ucf_constraints(
            cls,
            clocks,
            patterns
    ):
        """Generate UCF constraint lines from clocks and TIG patterns

        Args:
            clocks: List of (net_name, period_ns) tuples from CCF
            patterns: Dict of pattern_name -> bool indicating which patterns exist

        Returns:
            List of UCF constraint lines
        """
        lines = []

        # Generate PIN TPTHRU definitions for detected patterns
        if patterns['tig_clr']:
            lines.append('PIN "*tig_reg_clr*.CLR" TPTHRU = "ff_tig_clr";')
        if patterns['tig_pre']:
            lines.append('PIN "*tig_reg_pre*.PRE" TPTHRU = "ff_tig_pre";')
        if patterns['tig_d']:
            lines.append('PIN "*tig_reg_d*.D" TPTHRU = "ff_tig_d";')
        if patterns['tig_q']:
            lines.append('PIN "*tig_reg_q*.Q" TPTHRU = "ff_tig_q";')
#        if patterns['tig_static_d']:
#            lines.append('PIN "*tig_static_reg_d*" TPTHRU = "ff_tig_static_d";')
        if patterns['ff_cross']:
            lines.append('PIN "*cross_region_reg_d*.D" TPTHRU = "ff_cross";')

        # Generate clock constraints and TIG timespecs for each clock
        for net, period in clocks:
            token = cls.sanitize_token(net)

            # NET with TNM_NET and PERIOD
            lines.append(f'NET "{net}" TNM_NET="CCF_{token}_TNM" | PERIOD = {period};')

            # TIMEGRP definition
            lines.append(f'TIMEGRP "CCF_{token}_GRP" = "CCF_{token}_TNM";')

            # TIG timespecs from various TIG paths TO this clock group
            if patterns['tig_clr']:
                lines.append(f'TIMESPEC "TS_to_{token}_tig_clr" = THRU "ff_tig_clr" TO "CCF_{token}_GRP" TIG;')
            if patterns['tig_pre']:
                lines.append(f'TIMESPEC "TS_to_{token}_tig_pre" = THRU "ff_tig_pre" TO "CCF_{token}_GRP" TIG;')
            if patterns['tig_d']:
                lines.append(f'TIMESPEC "TS_to_{token}_tig_d" = THRU "ff_tig_d" TO "CCF_{token}_GRP" TIG;')
#            if patterns['tig_static_d']:
#                lines.append(f'TIMESPEC "TS_to_{token}_tig_static_d" = THRU "ff_tig_static_d" TO "CCF_{token}_GRP" TIG;')
            if patterns['tig_q']:
                lines.append(f'TIMESPEC "TS_to_{token}_tig_q" = FROM "CCF_{token}_GRP" THRU "ff_tig_q" TIG;')

        # Generate cross-domain resync constraints if cross_region pattern exists
        if patterns['ff_cross']:
            for i, (source_net, source_period) in enumerate(clocks):
                source_token = cls.sanitize_token(source_net)

                for j, (dest_net, dest_period) in enumerate(clocks):
                    if i == j:
                        continue

                    dest_token = cls.sanitize_token(dest_net)

                    # Use minimum period of source and dest
                    min_period = min(source_period, dest_period)

                    lines.append(
                        f'TIMESPEC "TS_from_{source_token}_to_{dest_token}_resync" = '
                        f'FROM "CCF_{source_token}_GRP" THRU "ff_cross" TO "CCF_{dest_token}_GRP" '
                        f'{min_period} ns DATAPATHONLY;'
                    )

        return lines


class CdcIseDispatcher(BaseDispatcher):
    """NSL CDC constraint generation dispatcher for ISE

    Generates Xilinx UCF constraints for NSL timing-insensitive constructs.

    Workflow:
    1. Waits for ISE EDIF netlist to be generated
    2. Reads CCF files from source tree (nsl-ccf file type)
    3. Parses netlist for NSL TIG patterns
    4. Generates UCF file with TPTHRU, TNM_NET, TIMEGRP, and TIMESPEC constraints
    5. Adds UCF file to fileset (ISE backend picks it up for NGDBUILD)

    Priority: 650 (runs after ISE EDIF conversion at 600)
    """

    def __init__(
            self,
            context,
    ):
        super().__init__(context, "nsl_cdc_ise", tool_name = "nsl")
        self._constraint_task = None

    async def process(
        self,
    ):
        """Process netlist and generate CDC constraints"""

        # Look for ISE EDIF netlist
        netlist_files = list(self.context.filter_pending(file_type=["ise-netlist"]))

        if not netlist_files:
            self.debug("No ise-netlist resource in build")
            return

        if not self._constraint_task:
            # Use first netlist file
            netlist_resource = netlist_files[0]

            # Define output UCF file
            ucf_file = self.context.output_path / "nsl_cdc_constraints.ucf"
            ucf_resource = self.context.get_resource(
                ucf_file,
                file_type='xilinx-ucf',
                typology=ResourceTypology.INTERMEDIATE,
                generated_by=self.name
            )

            self.debug("Creating NSL ISE EDIF to CDC constraint task")
            self.debug(f"Netlist: {netlist_resource}")
            self.debug(f"Output: {ucf_resource}")

            # Create constraint generation task
            self._constraint_task = CdcIseConstraintTask(
                dispatcher = self,
                outputs=[ucf_resource]
            )

            self._constraint_task.add_input(netlist_resource, consume = False)

        sources = list(self.context.filter_pending(file_type=["nsl-ccf"]))
        if sources:
            self.debug(f"Adding {len(sources)} CCF sources")
        for source in sources:
            self._constraint_task.add_input(source)

class CdcIsePass(BasePass):
    name = "nsl-cdc-ise"
    input_types = {"nsl-ccf", "ise-netlist"}
    output_types = {"xilinx-ucf"}

    def dispatchers(self, context):
        return [CdcIseDispatcher(context)]

class CdcIseBackend(BaseBackend):
    def __init__(self):
        super().__init__("gbs.plugin.nsl.cdc.ise")

    def contribute_passes(
        self,
        config,
        output_types,
        project_config,
        gbs_config,
    ):
        passes = []

        if output_types & {"xilinx-ucf"}:
            passes.append(CdcIsePass(config))

        return passes
