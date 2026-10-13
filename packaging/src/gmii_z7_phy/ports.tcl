# rx_clock_i only exists when the RX side has its own clock. Hide both
# the clock interface and its port otherwise, so the block shows a
# single clock.
set_property enablement_dependency {$indep_rx_clock_c} [ipx::get_bus_interfaces rx_clock_i -of_objects [ipx::current_core]]
set_property enablement_dependency {$indep_rx_clock_c} [ipx::get_ports rx_clock_i -of_objects [ipx::current_core]]
set_property driver_value 0 [ipx::get_ports rx_clock_i -of_objects [ipx::current_core]]

# The fake MDIO PHY, its address, link_up_i and mdio_resetn only exist
# with has_mdio_c.
set_property enablement_tcl_expr {$has_mdio_c} [ipx::get_user_parameters phy_addr_c -of_objects [ipx::current_core]]
set_property enablement_dependency {$has_mdio_c} [ipx::get_bus_interfaces mdio -of_objects [ipx::current_core]]
set_property enablement_dependency {$has_mdio_c} [ipx::get_bus_interfaces mdio_resetn -of_objects [ipx::current_core]]
foreach {port value} {mdio_mdc 1 mdio_o 1 mdio_t 1 link_up_i 0} {
    set_property enablement_dependency {$has_mdio_c} [ipx::get_ports $port -of_objects [ipx::current_core]]
    set_property driver_value $value [ipx::get_ports $port -of_objects [ipx::current_core]]
}
foreach port {mdio_i mdio_resetn} {
    set_property enablement_dependency {$has_mdio_c} [ipx::get_ports $port -of_objects [ipx::current_core]]
}

# Install the block-design propagation hook. gbs has no vivado-bd-tcl
# input type, so bd.tcl is copied into the packaged IP and registered
# here instead. Without it to_mac inherits no clock when rx_clock_i is
# hidden, because it is declared against rx_clock_i.
set core [ipx::current_core]
set root [get_property ROOT_DIRECTORY $core]
file mkdir [file join $root bd]
file copy -force [file join [file dirname [info script]] bd.tcl] [file join $root bd bd.tcl]

# The block design only runs hooks found in the Block Diagram file group
# (xilinx_blockdiagram), as Xilinx's own IPs do; in the utility group
# the file is packaged but never executed.
if {[llength [ipx::get_file_groups xilinx_blockdiagram -of_objects $core]] == 0} {
    ipx::add_file_group -type blockdiagram {} $core
}
set fg [ipx::get_file_groups xilinx_blockdiagram -of_objects $core]
ipx::add_file bd/bd.tcl $fg
set_property type tclSource [ipx::get_files bd/bd.tcl -of_objects $fg]
