# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  #Adding Group
  set Divisions [ipgui::add_group $IPINST -name "Divisions" -parent ${Page_0}]
  ipgui::add_param $IPINST -name "chunk0_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk1_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk2_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk3_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk4_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk5_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk6_count" -parent ${Divisions}
  ipgui::add_param $IPINST -name "chunk7_count" -parent ${Divisions}



}

proc update_PARAM_VALUE.chunk0_count { PARAM_VALUE.chunk0_count } {
	# Procedure called to update chunk0_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk0_count { PARAM_VALUE.chunk0_count } {
	# Procedure called to validate chunk0_count
	return true
}

proc update_PARAM_VALUE.chunk1_count { PARAM_VALUE.chunk1_count } {
	# Procedure called to update chunk1_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk1_count { PARAM_VALUE.chunk1_count } {
	# Procedure called to validate chunk1_count
	return true
}

proc update_PARAM_VALUE.chunk2_count { PARAM_VALUE.chunk2_count } {
	# Procedure called to update chunk2_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk2_count { PARAM_VALUE.chunk2_count } {
	# Procedure called to validate chunk2_count
	return true
}

proc update_PARAM_VALUE.chunk3_count { PARAM_VALUE.chunk3_count } {
	# Procedure called to update chunk3_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk3_count { PARAM_VALUE.chunk3_count } {
	# Procedure called to validate chunk3_count
	return true
}

proc update_PARAM_VALUE.chunk4_count { PARAM_VALUE.chunk4_count } {
	# Procedure called to update chunk4_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk4_count { PARAM_VALUE.chunk4_count } {
	# Procedure called to validate chunk4_count
	return true
}

proc update_PARAM_VALUE.chunk5_count { PARAM_VALUE.chunk5_count } {
	# Procedure called to update chunk5_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk5_count { PARAM_VALUE.chunk5_count } {
	# Procedure called to validate chunk5_count
	return true
}

proc update_PARAM_VALUE.chunk6_count { PARAM_VALUE.chunk6_count } {
	# Procedure called to update chunk6_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk6_count { PARAM_VALUE.chunk6_count } {
	# Procedure called to validate chunk6_count
	return true
}

proc update_PARAM_VALUE.chunk7_count { PARAM_VALUE.chunk7_count } {
	# Procedure called to update chunk7_count when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.chunk7_count { PARAM_VALUE.chunk7_count } {
	# Procedure called to validate chunk7_count
	return true
}

proc update_PARAM_VALUE.grouped_count { PARAM_VALUE.grouped_count PARAM_VALUE.chunk0_count PARAM_VALUE.chunk1_count PARAM_VALUE.chunk2_count PARAM_VALUE.chunk3_count PARAM_VALUE.chunk4_count PARAM_VALUE.chunk5_count PARAM_VALUE.chunk6_count PARAM_VALUE.chunk7_count } {
	# Procedure called to update grouped_count when any of the dependent parameters in the arguments change
    set chunk0_count [get_property value ${PARAM_VALUE.chunk0_count}]
    set chunk1_count [get_property value ${PARAM_VALUE.chunk1_count}]
    set chunk2_count [get_property value ${PARAM_VALUE.chunk2_count}]
    set chunk3_count [get_property value ${PARAM_VALUE.chunk3_count}]
    set chunk4_count [get_property value ${PARAM_VALUE.chunk4_count}]
    set chunk5_count [get_property value ${PARAM_VALUE.chunk5_count}]
    set chunk6_count [get_property value ${PARAM_VALUE.chunk6_count}]
    set chunk7_count [get_property value ${PARAM_VALUE.chunk7_count}]
    set grouped_count [expr $chunk0_count + $chunk1_count + $chunk2_count + $chunk3_count + $chunk4_count + $chunk5_count + $chunk6_count + $chunk7_count]
    set_property value $grouped_count ${PARAM_VALUE.grouped_count}
}

proc validate_PARAM_VALUE.grouped_count { PARAM_VALUE.grouped_count } {
	# Procedure called to validate grouped_count
	return true
}

proc update_MODELPARAM_VALUE.grouped_count { MODELPARAM_VALUE.grouped_count PARAM_VALUE.grouped_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.grouped_count}] ${MODELPARAM_VALUE.grouped_count}
}

proc update_MODELPARAM_VALUE.chunk0_count { MODELPARAM_VALUE.chunk0_count PARAM_VALUE.chunk0_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk0_count}] ${MODELPARAM_VALUE.chunk0_count}
}

proc update_MODELPARAM_VALUE.chunk1_count { MODELPARAM_VALUE.chunk1_count PARAM_VALUE.chunk1_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk1_count}] ${MODELPARAM_VALUE.chunk1_count}
}

proc update_MODELPARAM_VALUE.chunk2_count { MODELPARAM_VALUE.chunk2_count PARAM_VALUE.chunk2_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk2_count}] ${MODELPARAM_VALUE.chunk2_count}
}

proc update_MODELPARAM_VALUE.chunk3_count { MODELPARAM_VALUE.chunk3_count PARAM_VALUE.chunk3_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk3_count}] ${MODELPARAM_VALUE.chunk3_count}
}

proc update_MODELPARAM_VALUE.chunk4_count { MODELPARAM_VALUE.chunk4_count PARAM_VALUE.chunk4_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk4_count}] ${MODELPARAM_VALUE.chunk4_count}
}

proc update_MODELPARAM_VALUE.chunk5_count { MODELPARAM_VALUE.chunk5_count PARAM_VALUE.chunk5_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk5_count}] ${MODELPARAM_VALUE.chunk5_count}
}

proc update_MODELPARAM_VALUE.chunk6_count { MODELPARAM_VALUE.chunk6_count PARAM_VALUE.chunk6_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk6_count}] ${MODELPARAM_VALUE.chunk6_count}
}

proc update_MODELPARAM_VALUE.chunk7_count { MODELPARAM_VALUE.chunk7_count PARAM_VALUE.chunk7_count } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.chunk7_count}] ${MODELPARAM_VALUE.chunk7_count}
}

