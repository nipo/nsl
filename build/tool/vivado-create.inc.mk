$(call exclude-libs,unisim xilinxcorelib)

define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define _vivado-add-bd-before
	$(call file-append,$1,set f [add_files [file normalize {$2}]])
	$(call file-append,$1,reset_target Synthesis $$f)
	$(call file-append,$1,open_bd_design $$f)

endef

_VIVADO_VHDL_VERSION_2008 := VHDL 2008
_VIVADO_VHDL_VERSION_1993 := VHDL

generic-string = $1={\"$2\"}
generic-integer = $1=$2
generic-vector = $1=$2\'b$3
generic-bool-true = $1=1\'b1
generic-bool-false = $1=1\'b0
generic-bool = $(call generic-bool-$2,$1)

define _vivado-add-vhdl
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_sources_fileset_name [file normalize {$2}]])
	$(call file-append,$1,set_property -dict {"file_type" "$(_VIVADO_VHDL_VERSION_$($($2-library)-vhdl-version))" "library" "$($2-library)"} $$f)

endef

define _vivado-add-verilog
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_sources_fileset_name [file normalize {$2}]])
	$(call file-append,$1,set_property -dict {"file_type" "Verilog" "library" "$($2-library)"} $$f)

endef

define _vivado-add-xci
	$(call file-append,$1,set f [read_ip [file normalize {$2}]])
	$(call file-append,$1,set_property -dict { "library" "$($2-library)" "used_in" "synthesis implementation"} $$f)

endef
#	$(call file-append,$1,set_property generate_synth_checkpoint 1 $$f)

_VIVADO_CONSTRAINT_TYPE_xdc = XDC
_VIVADO_CONSTRAINT_TYPE_tcl = TCL

define _vivado-add-constraint
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_constr_fileset_name [file normalize {$2}]])
	$(call file-append,$1,set_property -dict {"file_type" "$(_VIVADO_CONSTRAINT_TYPE_$(lastword $(subst ., ,$2)))" "used_in" "synthesis implementation simulation"} $$f)

endef

define _vivado-add-implementation_constraint
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_constr_fileset_name [file normalize {$2}]])
	$(call file-append,$1,set_property -dict {"file_type" "$(_VIVADO_CONSTRAINT_TYPE_$(lastword $(subst ., ,$2)))" "used_in" "implementation"} $$f)

endef

define _vivado-add-synthesis_constraint
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_constr_fileset_name [file normalize {$2}]])
	$(call file-append,$1,set_property -dict {"file_type" "$(_VIVADO_CONSTRAINT_TYPE_$(lastword $(subst ., ,$2)))" "used_in" "synthesis implementation"} $$f)

endef

# Args:
#  $1: output file,
#  $2: Sources fileset name (should exist)
#  $2: Constraints fileset name (should exist)
define vivado-tcl-sources-append
	$(call file-append,$1,source $(BUILD_ROOT)/support/vivado-msg-suppress.tcl)
	$(call file-append,$1,set_property source_mgmt_mode DisplayOnly [current_project])
	$(call file-append,$1,set _sources_fileset_name "$2")
	$(call file-append,$1,set _constr_fileset_name "$3")
	$(call file-append,$1,set _sources_fileset [get_filesets "$$_sources_fileset_name"])
	$(call file-append,$1,set _constr_fileset [get_filesets "$$_constr_fileset_name"])
	$(foreach s,$(sources),$(call _vivado-add-$($s-language)-before,$1,$s))
	$(foreach s,$(sources),$(call _vivado-add-$($s-language),$1,$s))
	$(call _vivado-add-constraint,$1,$(BUILD_ROOT)/support/generic_timing_constraints_vivado.tcl)
	$(call _vivado-add-implementation_constraint,$1,$(BUILD_ROOT)/support/vivado-userid.tcl)
	$(call _vivado-add-implementation_constraint,$1,$(BUILD_ROOT)/support/vivado-drc.tcl)
	$(call file-append,$1,set_property "top_lib" "$(top-lib)" $$_sources_fileset)
	$(call file-append,$1,set_property "top" "$(top-entity)" $$_sources_fileset)
	$(call file-append,$1,set_property "generic" "$(topcell-generics)" $$_sources_fileset)
	$(call file-append,$1,set_param synth.elaboration.rodinMoreOptions {rt::set_parameter ignoreVhdlAssertStmts false})
	$(call file-append,$1,foreach {xci} [get_files -of_objects [get_filesets $$_sources_fileset_name] "*.xci"] {)
	$(call file-append,$1,    generate_target "synthesis implementation" $$xci)
	$(call file-append,$1,})

endef

define vivado-tcl-run
	$(SILENT)$(VIVADO_PREPARE) ; cd $(dir $1) ; vivado -nojournal -mode batch -source $(notdir $1)

endef

define vivado-tcl-cmd
	$(SILENT)$(VIVADO_PREPARE) ; vivado -nojournal -nolog -mode tcl <<< '$1'

endef

