# The output-side clock exists only for an asynchronous fifo.  Hide both
# the clock interface and its port so a synchronous instance shows a
# single clock.
set_property enablement_dependency {$clock_count_c > 1} [ipx::get_bus_interfaces out_clock_i -of_objects [ipx::current_core]]
set_property enablement_dependency {$clock_count_c > 1} [ipx::get_ports out_clock_i -of_objects [ipx::current_core]]
set_property driver_value 0 [ipx::get_ports out_clock_i -of_objects [ipx::current_core]]

# Install the block-design propagation hook.  gbs has no vivado-bd-tcl
# input type, so bd.tcl is copied into the packaged IP and registered
# here instead.  Without it the out interface inherits no clock in the
# clock_count_c = 1 configuration, because it is declared against the
# disabled out_clock_i.
set core [ipx::current_core]
set root [get_property ROOT_DIRECTORY $core]
file mkdir [file join $root bd]
file copy -force [file join [file dirname [info script]] bd.tcl] [file join $root bd bd.tcl]

if {[llength [ipx::get_file_groups xilinx_utilityxitfiles -of_objects $core]] == 0} {
    ipx::add_file_group -type utility {} $core
}
set fg [ipx::get_file_groups xilinx_utilityxitfiles -of_objects $core]
ipx::add_file bd/bd.tcl $fg
set_property type tclSource [ipx::get_files bd/bd.tcl -of_objects $fg]
