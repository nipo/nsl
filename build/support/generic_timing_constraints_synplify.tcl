# -*- tcl -*-

# Ignore Output path of registers named *tig_reg_d*
# Ignore Input path of registers named *tig_reg_q*
# Ignore Reset path of registers named *tig_reg_clr*
# Ignore path through nets named *async_net*
# Apply cross-region paths for registers named *cross_region_reg_d*
# Apply read-clock timings for TDP-Ram that were demoted to Registers

set_false_path -through [get_pins -quiet -hier *tig_reg_clr*/CLR]
#set_false_path -through [get_pins -quiet -hier -regexp -filter {name=~".*tig_reg_(q.*/[ZOQ]|d.*/[DI]).*"}]
set_false_path -through [get_pins -quiet -hier {*tig_reg_q*/Z}]
set_false_path -through [get_pins -quiet -hier {*tig_reg_q*/O}]
set_false_path -through [get_pins -quiet -hier {*tig_reg_q*/Q}]
set_false_path -through [get_pins -quiet -hier {*tig_reg_d*/D}]
set_false_path -through [get_pins -quiet -hier {*tig_reg_d*/I}]
set_false_path -through [get_nets -quiet -hier {*tig_reg_q*}]
set_false_path -through [get_nets -quiet -hier {*tig_reg_d*}]
set_false_path -through [get_nets -quiet -hier {*_async_net*}]

set reg_input_pins [get_pins -hier -regexp -filter {name=~.*cross_region_reg_d.*/D}]
set dpram_output_pins [get_pins -hier -regexp -filter {name=~".*dpram_reg.*/[OQ]"}]

foreach {dest_clock} [all_clocks] {
    foreach {source_clock} [all_clocks] {
        if {$dest_clock == $source_clock} {
            continue
        }

        set dest_clock_period  [get_property -quiet PERIOD $dest_clock]
        set source_clock_period  [get_property -quiet PERIOD $source_clock]
        set_max_delay -from $source_clock -to $dest_clock -through $reg_input_pins $source_clock_period -datapath_only
        set_bus_skew  -from $source_clock -to $dest_clock -through $reg_input_pins [expr min ($source_clock_period, $dest_clock_period)]

        set_max_delay -from $source_clock -to $dest_clock -through $dpram_output_pins $dest_clock_period -datapath_only
        set_bus_skew  -from $source_clock -to $dest_clock -through $dpram_output_pins [expr min ($source_clock_period, $dest_clock_period)]
    }
}
