set_property enablement_dependency {$chunk1_count > 0} [ipx::get_bus_interfaces chunk1 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk2_count > 0} [ipx::get_bus_interfaces chunk2 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk3_count > 0} [ipx::get_bus_interfaces chunk3 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk4_count > 0} [ipx::get_bus_interfaces chunk4 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk5_count > 0} [ipx::get_bus_interfaces chunk5 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk6_count > 0} [ipx::get_bus_interfaces chunk6 -of_objects [ipx::current_core]]
set_property enablement_dependency {$chunk7_count > 0} [ipx::get_bus_interfaces chunk7 -of_objects [ipx::current_core]]

set div [ipgui::add_group -name {Divisions} -component [ipx::current_core] -parent [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core] ] -display_name {Divisions} -layout {vertical}]

ipgui::move_param -component [ipx::current_core] -order 0 [ipgui::get_guiparamspec -name "chunk0_count" -component [ipx::current_core]] -parent $div
set_property value_validation_range_minimum 1 [ipx::get_user_parameters chunk0_count -of_objects [ipx::current_core]]
ipgui::move_param -component [ipx::current_core] -order 1 [ipgui::get_guiparamspec -name "chunk1_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 2 [ipgui::get_guiparamspec -name "chunk2_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 3 [ipgui::get_guiparamspec -name "chunk3_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 4 [ipgui::get_guiparamspec -name "chunk4_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 5 [ipgui::get_guiparamspec -name "chunk5_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 6 [ipgui::get_guiparamspec -name "chunk6_count" -component [ipx::current_core]] -parent $div
ipgui::move_param -component [ipx::current_core] -order 7 [ipgui::get_guiparamspec -name "chunk7_count" -component [ipx::current_core]] -parent $div

ipgui::remove_param -component [ipx::current_core] [ipgui::get_guiparamspec -name "grouped_count" -component [ipx::current_core]]

set_property enablement_resolve_type generated [ipx::get_user_parameters grouped_count -of_objects [ipx::current_core]]

