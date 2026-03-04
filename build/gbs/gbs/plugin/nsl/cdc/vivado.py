"""NSL CDC Constraint Inserter for Xilinx Vivado

As vivado allows to inspect the netlist dynamically from TCL, we do
not need to generate anything dynamically. We only need to inject a
TCL file in the build.

"""

from pathlib import Path
import re
from typing import Any
import sys

from gbs.base import *
from gbs.build.context import BuildContext
from gbs.build.task import Task, ResourceTypology

constraints_paylaod = r"""# -*- tcl -*-
#
# Here, we use a little (Vivado-specific ?) TCL to apply timing
# constraints for all implicitly constrained cells that have relevant
# names:

# Ignore Output path of registers named *tig_reg_d*
# Ignore Input path of registers named *tig_reg_q*
# Ignore Reset path of registers named *tig_reg_clr*
# Ignore Preset path of registers named *tig_reg_pre*
# Ignore Input/Output path of registers named *tig_static_reg_d*
# Ignore path through nets named *async_net*
# Apply cross-region paths for registers named *cross_region_reg_d*
# Apply read-clock timings for TDP-Ram that were demoted to Registers

set_false_path -quiet -through [get_pins -quiet -hier *tig_reg_clr*/CLR]
set_false_path -quiet -through [get_pins -quiet -hier *tig_reg_pre*/PRE]
set_false_path -quiet -through [get_pins -quiet -hier -regexp -filter {name=~".*tig_reg_(q.*/[OQ]|d.*/[ID])"}]
set_false_path -quiet -through [get_nets -quiet -hier {*_async_net*}]
set_false_path -quiet -through [get_pins -quiet -hier -regexp -filter {name=~".*tig_static_reg_d(.*/[OQ]|.*/[ID])"}]

## Cross-region resynchronization cells

set reg_input_pins [get_pins -quiet -hier -regexp -filter {name=~.*cross_region_reg_d.*/D}]
common::send_msg_id "NSL-1-01" "INFO" "Found [llength $reg_input_pins] pins for cross region"
    
if {[version -short] < 2022} {
    set reg_cells [get_cells -quiet -of_objects $reg_input_pins]
    
    foreach {dest_clock} [get_clocks -quiet -of_objects $reg_cells] {
        set source_clocks [get_clocks -quiet -of_objects [all_fanin -flat -only_cells $reg_input_pins]]
        foreach {source_clock} $source_clocks {
            if {$dest_clock == $source_clock} {
                continue
            }
    
            common::send_msg_id "NSL-1-02" "INFO" "From $source_clock to $dest_clock"
    
            set dest_clock_period  [get_property -quiet -min PERIOD $dest_clock]
            set source_clock_period  [get_property -quiet -min PERIOD $source_clock]
            set_max_delay -from $source_clock -to $dest_clock -through $reg_input_pins $source_clock_period -datapath_only
            set_bus_skew -quiet -from $source_clock -to $dest_clock -through $reg_input_pins [expr min ($source_clock_period, $dest_clock_period)]
        }
    }
} else {
    foreach {reg_input_pin} $reg_input_pins {
        set dst_cells [get_cells -quiet -of_objects $reg_input_pin]
        set src_cells [all_fanin -flat -only_cells $reg_input_pin]
        
        foreach {dst_clock} [get_clocks -quiet -of_objects $dst_cells] {
            foreach {src_clock} [get_clocks -quiet -of_objects $src_cells] {
                if {$src_clock == $dst_clock} {
                    continue
                }
                
                common::send_msg_id "NSL-1-02" "INFO" "From $src_cells to $dst_cells"
                
                set dst_clock_period [get_property -quiet -min PERIOD $dst_clock]
                set src_clock_period [get_property -quiet -min PERIOD $src_clock]
                set_max_delay -from $src_clock -to $dst_clock -through $reg_input_pins $src_clock_period -datapath_only
                set_bus_skew -from $src_cells -to $dst_cells [expr min ($src_clock_period, $dst_clock_period)]
            }
        }
    }
}

## Dual-port rams
# TDP-RAM that get downgraded to FF or RAMB actually loose read clock.
# We have to insert constraints that match the read-clock timings.
    
set dpram_output_pins [get_pins -quiet -hier -regexp -filter {name=~".*dpram_reg.*/[OQ]"}]
common::send_msg_id "NSL-2-01" "INFO" "Found [llength $dpram_output_pins] pins for FF-Ram cross region"
    
if {[version -short] < 2022} {
    set dpram_cells [get_cells -of_objects $dpram_output_pins]
    
    foreach {source_clock} [get_clocks -quiet -of_objects $dpram_cells] {
        set dest_clocks [get_clocks -quiet -of_objects [all_fanout -flat -only_cells $dpram_output_pins]]
        foreach {dest_clock} $dest_clocks {
            if {$dest_clock == $source_clock} {
                continue
            }
    
            common::send_msg_id "NSL-2-02" "INFO" "From $source_clock to $dest_clock"
    
            set dest_clock_period  [get_property -quiet -min PERIOD $dest_clock]
            set source_clock_period  [get_property -quiet -min PERIOD $source_clock]
            set_max_delay -from $source_clock -to $dest_clock -through $dpram_output_pins $dest_clock_period -datapath_only
            set_bus_skew -quiet -from $source_clock -to $dest_clock -through $dpram_output_pins [expr min ($source_clock_period, $dest_clock_period)]
        }
    }
} else {
    foreach {dpram_output_pin} $dpram_output_pins {
        set src_cells [get_cells -quiet -of_objects $dpram_output_pin]
        set dst_cells [all_fanout -flat -only_cells $dpram_output_pin]
        
        foreach {dst_clock} [get_clocks -quiet -of_objects $dst_cells] {
            foreach {src_clock} [get_clocks -quiet -of_objects $src_cells] {
                if {$src_clock == $dst_clock} {
                    continue
                }
                
                common::send_msg_id "NSL-2-02" "INFO" "From $src_cells to $dst_cells"
                
                set dst_clock_period [get_property -quiet -min PERIOD $dst_clock]
                set src_clock_period [get_property -quiet -min PERIOD $src_clock]
                set_max_delay -from $src_clock -to $dst_clock -through $dpram_output_pins $dst_clock_period -datapath_only
                set_bus_skew -from $src_cells -to $dst_cells [expr min ($src_clock_period, $dst_clock_period)]
            }
        }
    }
}

foreach {bscan} [get_cells -hier {jtag_bscane2_inst}] {
    common::send_msg_id "NSL-3-02" "INFO" "Adding TCK clock for $bscan"
    create_clock -period 20.000 [get_pins -filter {REF_PIN_NAME=~TCK} -of $bscan]
}
"""

class CdcVivadoConstraintTask(Task):
    """Generate NSL TCL constraints for Vivado"""

    def __init__(
        self,
        dispatcher,
        outputs
    ):
        super().__init__(
            dispatcher,
            "nsl_cdc_vivado_constraints",
            inputs=[],
            outputs=outputs,
            description="Generate NSL CDC constraints for Vivado"
        )

    async def work(self):
        """Generate TCL constraints"""

        resource, = self.outputs_of_type("xilinx-constraints-tcl")

        resource.path.parent.mkdir(parents=True, exist_ok=True)
        if not resource.path.exists() or resource.path.read_text() != constraints_paylaod:
            resource.path.write_text(constraints_paylaod)

class CdcVivadoDispatcher(BaseDispatcher):
    """NSL CDC constraint generation dispatcher for Vivado
    """

    def __init__(
            self,
            context,
    ):
        super().__init__(context, "nsl_cdc_vivado", tool_name = "nsl")
        self._constraint_task = None

    async def process(
        self,
    ):
        """Process netlist and generate CDC constraints"""

        if not self._constraint_task and self.context.filter_pending(file_type="vivado-bitstream"):
            # Define output file
            file = self.context.output_path / "nsl_cdc_constraints.tcl"
            resource = self.context.get_resource(
                file,
                file_type='xilinx-constraints-tcl',
                typology=ResourceTypology.INTERMEDIATE,
                generated_by=self.name
            )

            # Create constraint generation task
            self._constraint_task = CdcVivadoConstraintTask(
                dispatcher = self,
                outputs=[resource]
            )
