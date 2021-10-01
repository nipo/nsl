ISE = /opt/Xilinx/14.7/ISE_DS
ISE_PREPARE = source $(ISE)/settings64.sh > /dev/null

SHELL=/bin/bash

$(call exclude-libs,unisim)

tmp-dir := planahead-tmp

define hdl_add
	echo 'add_files -fileset sources_1 -norecurse $1' >> $@
	$(SILENT)echo 'set_property library "$($1-library)" [get_files $1]' >> $@
	$(SILENT)
endef

define constraint_add
	echo 'add_files -fileset constrs_1 -norecurse $1' >> $@
	$(SILENT)
endef

source_add=$(if $(filter constraint,$($1-language)),$(call constraint_add,$1),$(call hdl_add,$1))

all: $(target)/$(target).ppr

$(tmp-dir)/ingress/create.tcl: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(SILENT)echo 'create_project -force proj_tmp projdir -part $(target_part)$(target_package)$(target_speed)' >> $@
	$(SILENT)echo 'set_property target_language VHDL [current_project]' >> $@
	$(SILENT)echo 'set_property source_mgmt_mode DisplayOnly [current_project]' >> $@
	$(SILENT)$(foreach s,$(sources),$(call source_add,$s))
	$(SILENT)echo 'set_property top $(top-entity) [get_filesets sources_1]' >> $@
	$(SILENT)echo 'save_project_as -force $(target) ../../$(target)' >> $@

$(target)/$(target).ppr: $(tmp-dir)/ingress/create.tcl
	-$(SILENT)rm -r $(target)/
	$(SILENT)$(ISE_PREPARE) ; cd $(dir $<) ; planAhead -mode batch -source $(notdir $<)

clean-dirs += $(tmp-dir)/ingress
clean-dirs += $(target)
