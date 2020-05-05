set_property enablement_dependency {$master_port_count > 1} [ipx::get_bus_interfaces m_1 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 2} [ipx::get_bus_interfaces m_2 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 3} [ipx::get_bus_interfaces m_3 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 4} [ipx::get_bus_interfaces m_4 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 5} [ipx::get_bus_interfaces m_5 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 6} [ipx::get_bus_interfaces m_6 -of_objects [ipx::current_core]]
set_property enablement_dependency {$master_port_count > 7} [ipx::get_bus_interfaces m_7 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 1} [ipx::get_bus_interfaces s_1 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 2} [ipx::get_bus_interfaces s_2 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 3} [ipx::get_bus_interfaces s_3 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 4} [ipx::get_bus_interfaces s_4 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 5} [ipx::get_bus_interfaces s_5 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 6} [ipx::get_bus_interfaces s_6 -of_objects [ipx::current_core]]
set_property enablement_dependency {$slave_port_count > 7} [ipx::get_bus_interfaces s_7 -of_objects [ipx::current_core]]

set rt [ipgui::add_group -name {Routing tables} -component [ipx::current_core] -parent [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ] -display_name {Routing tables} -layout {horizontal}]
set crt [ipgui::add_group -name {Command} -component [ipx::current_core] -parent $rt -display_name {Command routing table} -layout {vertical}]
set rrt [ipgui::add_group -name {Response} -component [ipx::current_core] -parent $rt -display_name {Response routing table} -layout {vertical}]

ipgui::move_param -component [ipx::current_core] -order 0 [ipgui::get_guiparamspec -name "cmd_dest_0" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "cmd_dest_1" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 2 [ipgui::get_guiparamspec -name "cmd_dest_2" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 3 [ipgui::get_guiparamspec -name "cmd_dest_3" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 4 [ipgui::get_guiparamspec -name "cmd_dest_4" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 5 [ipgui::get_guiparamspec -name "cmd_dest_5" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 6 [ipgui::get_guiparamspec -name "cmd_dest_6" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 7 [ipgui::get_guiparamspec -name "cmd_dest_7" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 8 [ipgui::get_guiparamspec -name "cmd_dest_8" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 9 [ipgui::get_guiparamspec -name "cmd_dest_9" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 10 [ipgui::get_guiparamspec -name "cmd_dest_10" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 11 [ipgui::get_guiparamspec -name "cmd_dest_11" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 12 [ipgui::get_guiparamspec -name "cmd_dest_12" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 13 [ipgui::get_guiparamspec -name "cmd_dest_13" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 14 [ipgui::get_guiparamspec -name "cmd_dest_14" -component [ipx::current_core]] -parent $crt
ipgui::move_param -component [ipx::current_core] -order 15 [ipgui::get_guiparamspec -name "cmd_dest_15" -component [ipx::current_core]] -parent $crt

ipgui::move_param -component [ipx::current_core] -order 0 [ipgui::get_guiparamspec -name "rsp_dest_0" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "rsp_dest_1" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 2 [ipgui::get_guiparamspec -name "rsp_dest_2" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 3 [ipgui::get_guiparamspec -name "rsp_dest_3" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 4 [ipgui::get_guiparamspec -name "rsp_dest_4" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 5 [ipgui::get_guiparamspec -name "rsp_dest_5" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 6 [ipgui::get_guiparamspec -name "rsp_dest_6" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 7 [ipgui::get_guiparamspec -name "rsp_dest_7" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 8 [ipgui::get_guiparamspec -name "rsp_dest_8" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 9 [ipgui::get_guiparamspec -name "rsp_dest_9" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 10 [ipgui::get_guiparamspec -name "rsp_dest_10" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 11 [ipgui::get_guiparamspec -name "rsp_dest_11" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 12 [ipgui::get_guiparamspec -name "rsp_dest_12" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 13 [ipgui::get_guiparamspec -name "rsp_dest_13" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 14 [ipgui::get_guiparamspec -name "rsp_dest_14" -component [ipx::current_core]] -parent $rrt
ipgui::move_param -component [ipx::current_core] -order 15 [ipgui::get_guiparamspec -name "rsp_dest_15" -component [ipx::current_core]] -parent $rrt
