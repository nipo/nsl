VIVADO = /opt/Xilinx/Vivado/2017.4
VIVADO_PREPARE = source $(VIVADO)/settings64.sh > /dev/null

SHELL=/bin/bash

tmp-dir := vivado-tmp

define source_add
	echo 'add_files -norecurse $1' >> $@
	$(SILENT)echo 'set_property library "$($1-library)" [get_files $1]' >> $@
	$(SILENT)
endef

define constraint_add
	echo 'add_files -fileset constrs_1 -norecurse $1' >> $@
	$(SILENT)
endef

all: $(target)/$(target).xpr

$(tmp-dir)/ingress/create.tcl: $(sources) $(constraints) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(SILENT)echo 'create_project -force proj_tmp projdir -part $(target_part)$(target_package)$(target_speed)' >> $@
	$(SILENT)echo 'set_property target_language VHDL [current_project]' >> $@
	$(SILENT)echo 'set_property source_mgmt_mode DisplayOnly [current_project]' >> $@
	$(SILENT)$(foreach s,$(sources),$(call source_add,$s))
	$(SILENT)$(foreach s,$(constraints),$(call constraint_add,$s))
	$(SILENT)echo 'set_property top $(top-entity) [get_filesets sources_1]' >> $@
	$(SILENT)echo 'update_compile_order -fileset sources_1' >> $@
	$(SILENT)echo 'save_project_as -force $(target) ../../$(target)' >> $@

$(target)/$(target).xpr: $(tmp-dir)/ingress/create.tcl
	-$(SILENT)rm -r $(target)/
	$(SILENT)$(VIVADO_PREPARE) ; cd $(dir $<) ; vivado -mode batch -source $(notdir $<)

clean-dirs += $(tmp-dir)/ingress
clean-dirs += $(target)
