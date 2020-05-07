define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define _vivado-append-bd-before
	$(call file-append,$1,set fn [file normalize {$2}])
	$(call file-append,$1,add_files $$fn)
	$(call file-append,$1,reset_target Synthesis [get_files $$fn])
	$(call file-append,$1,open_bd_design $$fn)

endef

_VIVADO_VHDL_VERSION_08 := VHDL 2008
_VIVADO_VHDL_VERSION_93 := VHDL

define _vivado-add-vhdl
	$(call file-append,$1,set fn [file normalize {$2}])
	$(call file-append,$1,set f [add_files -norecurse -fileset $$sources_fileset $$fn])
	$(call file-append,$1,set_property "file_type" "$(_VIVADO_VHDL_VERSION_$($($1-library)-vhdl-version))" $$f)
	$(call file-append,$1,set_property "library" $($2-library) $$f)

endef

define _vivado-add-verilog
	$(call file-append,$1,set fn [file normalize {$2}])
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_sources_fileset $$fn])
	$(call file-append,$1,set_property "file_type" "Verilog" $$f)
	$(call file-append,$1,set_property "library" $($2-library) $$f)

endef

_VIVADO_CONSTRAINT_TYPE_xcf = XCF
_VIVADO_CONSTRAINT_TYPE_tcl = TCL

define _vivado-add-constraint
	$(call file-append,$1,set fn [file normalize {$2}])
	$(call file-append,$1,set f [add_files -norecurse -fileset $$_constr_fileset $$fn])
	$(call file-append,$1,set_property "file_type" "$(_VIVADO_CONSTRAINT_TYPE_$(lastword $(subst ., ,$1)))" $$f)

endef

# Args:
#  $1: output file,
#  $2: Sources fileset name (should exist)
#  $2: Constraints fileset name (should exist)
define vivado-tcl-sources-append
	$(call file-append,$1,set_property source_mgmt_mode DisplayOnly [current_project])
	$(call file-append,$1,set _sources_fileset [get_filesets $2])
	$(call file-append,$1,set _constr_fileset [get_filesets $3])
	$(foreach s,$(sources),$(call _vivado-add-$($s-language)-before,$1,$s))
	$(foreach s,$(sources),$(call _vivado-add-$($s-language),$1,$s))
	$(call file-append,$1,set_property "top" "$(top-lib).$(top-entity)" [get_filesets sources_1])

endef

define vivado-tcl-run
	$(SILENT)$(VIVADO_PREPARE) ; cd $(dir $1) ; vivado -mode batch -source $(notdir $1)

endef

