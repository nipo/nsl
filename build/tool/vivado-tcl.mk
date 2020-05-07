all: sources.tcl

define append
	$(SILENT)echo '$2' >> $1
endef

define append_bd
	$(call append,$1,set fn [file normalize {$2}])
	$(call append,$1,set f [add_files -norecurse -fileset $$sources_fileset $$fn])
	$(call append,$1,set_property "library" $($2-library) $$f)

endef

define append_vhdl_source
	$(call append,$1,set fn [file normalize {$2}])
	$(call append,$1,set f [add_files -norecurse -fileset $$sources_fileset $$fn])
	$(call append,$1,set_property "file_type" "VHDL 2008" $$f)
	$(call append,$1,set_property "library" $($2-library) $$f)

endef

define project_load_sources
	$(call append,$1,set_property source_mgmt_mode DisplayOnly [current_project])
	$(call append,$1,set sources_fileset [get_filesets sources_1])
	$(foreach s,$(all-bd-sources),$(call append_bd,$1,$s))
	$(foreach s,$(sources),$(call append_$($s-language)_source,$1,$s))
	$(call append,$1,set_property "top" "$(top-lib).$(top-entity)" [get_filesets sources_1])

endef

sources.tcl: $(sources) $(MAKEFILE_LIST)
	$(SILENT)> $@
	$(SILENT)$(call project_load_sources,$@)
