VIVADO = /opt/Xilinx/Vivado/2017.4
PAR_OPTS = -ol high
VIVADO_PREPARE = source $(VIVADO)/settings64.sh > /dev/null
target ?= $(ip-vendor)_$(ip-library)_$(ip-name)_$(ip-version)

SHELL=/bin/bash

build-dir := $(target)-build

define source_add
	echo 'set fname [file normalize "$1"]' >> $@
	$(SILENT)echo 'add_files -norecurse -fileset $$srcset_obj [list "$$fname"]' >> $@
	$(SILENT)echo 'set fobj [get_files -of_object $$srcset_obj [list "*$$fname"]]' >> $@
	$(SILENT)echo 'set_property "file_type" "$($1-language)" $$fobj' >> $@
	$(SILENT)echo 'set_property "library" "$($1-library)" $$fobj' >> $@
	$(SILENT)echo 'if { $$last_fobj != "" } { reorder_files -after [get_property name $$last_fobj] [get_property name $$fobj] }' >> $@
	$(SILENT)echo 'set last_fobj $$fobj' >> $@
	$(SILENT)
endef

define constraint_add
	echo 'set fname [file normalize "$1"]' >> $@
	$(SILENT)echo 'add_files -norecurse -fileset $$cstrset_obj [list "$$fname"]' >> $@
	$(SILENT)echo 'set fobj [get_files -of_object $$cstrset_obj [list "*$$fname"]]' >> $@
	$(SILENT)echo 'set_property "file_type" "$2" $$fobj' >> $@
	$(SILENT)echo 'set_property "library" "$($1-library)" $$fobj' >> $@
	$(SILENT)echo 'if { $$last_fobj != "" } { reorder_files -after [get_property name $$last_fobj] [get_property name $$fobj] }' >> $@
	$(SILENT)echo 'set last_fobj $$fobj' >> $@
	$(SILENT)
endef

all: $(target).zip

$(build-dir)/ingress/create.tcl: $(sources) $(ip-packaging-scripts) $(vivado-init-tcl) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(SILENT)echo 'create_project -force $(ip-name) .  -part $(target_part)$(target_package)$(target_speed)' >> $@
	$(SILENT)for f in $(vivado-init-tcl) ; do \
		cat $$f >> $@ ; \
	done
	$(SILENT)echo 'set_property -name "target_language" -value "VHDL" -objects [current_project]' >> $@
	$(SILENT)echo 'update_ip_catalog -rebuild' >> $@
#	$(SILENT)echo 'debug::add_scope scope HACG' >> $@
#	$(SILENT)echo 'debug::add_scope scope HACGIP' >> $@
	$(SILENT)echo 'debug::set_visibility 10' >> $@
	$(SILENT)echo 'debug::set_trace_verbosity -verbose' >> $@
	$(SILENT)echo 'set_property source_mgmt_mode DisplayOnly [current_project]' >> $@
	$(SILENT)echo 'set srcset_obj [get_filesets sources_1]' >> $@
	$(SILENT)echo 'set cstrset_obj [get_filesets sources_1]' >> $@
	$(SILENT)echo 'set last_fobj ""' >> $@
	$(SILENT)$(foreach s,$(sources),$(call source_add,$s))
	$(SILENT)echo 'set_property -name "top" -value "$(top-entity)" -objects $$srcset_obj' >> $@
#	$(SILENT)echo 'launch_runs synth_1 -jobs 6' >> $@
#	$(SILENT)echo 'wait_on_run synth_1' >> $@
	$(SILENT)echo 'ipx::package_project -root_dir ../ip -vendor $(ip-vendor) -library $(ip-library) -taxonomy $(ip-taxonomy) -import_files -set_current false' >> $@
	$(SILENT)echo 'ipx::unload_core ../ip/component.xml' >> $@
	$(SILENT)echo 'ipx::edit_ip_in_project -upgrade true -name tmp_edit_project -directory ../ip ../ip/component.xml' >> $@
	$(SILENT)for f in $(ip-packaging-scripts) ; do \
		cat $$f >> $@ ; \
	done
	$(SILENT)echo 'set_property display_name {$(ip-display-name)} [ipx::current_core]' >> $@
	$(SILENT)echo 'set_property name {$(ip-name)} [ipx::current_core]' >> $@
	$(SILENT)echo 'set_property core_revision {$(ip-revision)} [ipx::current_core]' >> $@
	$(SILENT)echo 'set_property supported_families [list $(target_families) Pre-Production] [ipx::current_core]' >> $@
	$(SILENT)echo 'set_property description {$(ip-description)} [ipx::current_core]' >> $@
	$(SILENT)echo 'ipx::create_xgui_files [ipx::current_core]' >> $@
	$(SILENT)echo 'ipx::update_checksums [ipx::current_core]' >> $@
	$(SILENT)echo 'ipx::save_core [ipx::current_core]' >> $@
	$(SILENT)echo 'close_project -delete' >> $@

$(build-dir)/ingress/synth.tcl: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(SILENT)echo 'create_project -force $(ip-name) . -part $(target_part)$(target_package)$(target_speed)' >> $@
	$(SILENT)echo 'set_property -name "target_language" -value "VHDL" -objects [current_project]' >> $@
	$(SILENT)echo 'update_ip_catalog -rebuild' >> $@
	$(SILENT)echo 'set_property source_mgmt_mode DisplayOnly [current_project]' >> $@
	$(SILENT)echo 'set srcset_obj [get_filesets sources_1]' >> $@
	$(SILENT)echo 'set cstrset_obj [get_filesets sources_1]' >> $@
	$(SILENT)echo 'set last_fobj ""' >> $@
	$(SILENT)$(foreach s,$(sources),$(call source_add,$s))
	$(SILENT)echo 'set_property -name "top" -value "$(top-entity)" -objects $$srcset_obj' >> $@
	$(SILENT)echo 'launch_runs synth_1 -jobs 6' >> $@
	$(SILENT)echo 'wait_on_run synth_1' >> $@

synth: $(build-dir)/ingress/synth.tcl
	$(SILENT)mkdir -p $(build-dir)/synth_proj
	-$(SILENT)rm -r $(build-dir)/ip
	$(SILENT)cd $(build-dir)/synth_proj ; \
	vivado -mode batch -source ../ingress/$(notdir $<)

$(build-dir)/ip/component.xml: $(build-dir)/ingress/create.tcl
	$(SILENT)mkdir -p $(build-dir)/proj
	-$(SILENT)rm -r $(build-dir)/ip
	$(SILENT)cd $(build-dir)/proj ; \
	vivado -mode batch -source ../ingress/$(notdir $<)

$(target).zip: $(build-dir)/ip/component.xml
	$(SILENT)cd $(build-dir)/ip ; \
	zip -r9D ../../$@ .

ifneq ($(ip_repo_path),)

all: $(ip_repo_path)/packs/$(target).zip $(ip_repo_path)/module/$(ip-library)/$(ip-name)/component.xml

$(ip_repo_path)/packs/$(target).zip: $(target).zip
	cp $< $@

$(ip_repo_path)/module/$(ip-library)/$(ip-name)/component.xml: $(target).zip
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	unzip -d $(dir $@) $<

endif

clean-dirs += $(build-dir)/ingress
clean-dirs += $(build-dir)/ip
clean-dirs += $(build-dir)/proj
clean-dirs += $(build-dir)/synth_proj
clean-dirs += $(build-dir)
clean-files += $(build-dir)/ingress/create.tcl
clean-files += $(build-dir)/ip/component.xml
clean-files += $(target).zip
