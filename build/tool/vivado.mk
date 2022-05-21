VIVADO = /opt/Xilinx/Vivado/2017.4
VIVADO_PREPARE = source $(VIVADO)/settings64.sh > /dev/null

SHELL=/bin/bash

synth-reports = $(build-dir)/synth.rpt
link-reports = $(build-dir)/link_opt_drc.rpt
link-reports += $(synth-reports)
placed-reports = $(build-dir)/placed_io.rpt
placed-reports += $(build-dir)/placed_usage.rpt
placed-reports += $(build-dir)/placed_control_sets.rpt
placed-reports += $(link-reports)
routed-reports = $(build-dir)/routed_drc.rpt
routed-reports = $(build-dir)/routed_methodology.rpt
routed-reports = $(build-dir)/routed_power.rpt
routed-reports = $(build-dir)/routed_route_status.rpt
routed-reports = $(build-dir)/routed_timing_summary.rpt
routed-reports = $(build-dir)/routed_incremental_reuse.rpt
routed-reports = $(build-dir)/routed_clock_utilization.rpt
routed-reports += $(placed-reports)

include $(TOOL_ROOT)/vivado-create.inc.mk

all:

$(target).bit: $(build-dir)/bitstream.bit
	cp $< $@

define append_constraint_synth
	$(if $(filter %.xdc,$2),$(call file-append,$1,read_xdc $2))	

endef

define append_xci_synth
	$(call file-append,$1,read_ip -quiet $2)

endef

append_xci_link=$(value append_xci_synth)

define append_dcp_link
	$(call file-append,$1,add_files -quiet $2)

endef

define append_dcp_link
# WTF

endef

define read_checkpoint
	$(foreach s,$(sources),$(call file-append_$($s-language)_link,$1,$s))
	$(call file-append,$1,link_design -top $(top-entity) -part $(target_part)$(target_package)$(target_speed))
	$(call file-append,$1,open_checkpoint -quiet $2)

endef

define project_init
	$(call file-append,$1,create_project -in_memory -part $(target_part)$(target_package)$(target_speed))
	$(SILENT)for f in $(vivado-init-tcl) ; do \
		cat $$f >> $1 ; \
	done
endef

$(build-dir)/sources.tcl: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call vivado-tcl-sources-append,$@,sources_1,constrs_1)

$(build-dir)/$(target)-xpr-gen.tcl: $(build-dir)/sources.tcl $(vivado-init-tcl) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call project_init,$@)
	$(call file-append,$@,source sources.tcl)
	$(call file-append,$@,save_project_as -force $(target) ../project)

project/$(target).xpr: $(build-dir)/$(target)-xpr-gen.tcl
	$(call vivado-tcl-run,$<)

$(build-dir)/synth.dcp: $(sources) $(vivado-init-tcl) $(MAKEFILE_LIST)
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call vivado-tcl-sources-append,$@.tcl,sources_1,constrs_1)
	$(call file-append,$@,set_param synth.elaboration.rodinMoreOptions {rt::set_parameter ignoreVhdlAssertStmts false})
	$(call file-append,$@.tcl,synth_design -top $(top-entity) -part $(target_part)$(target_package)$(target_speed) -assert)
	$(call file-append,$@.tcl,write_checkpoint -force -noxdef $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

#	$(call file-append,$@.tcl,set_param constraints.enableBinaryConstraints false)

$(build-dir)/synth.rpt: $(build-dir)/synth.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_utilization -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/link_opt.dcp: $(build-dir)/synth.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,opt_design)
	$(call file-append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/link_opt_drc.rpt: $(build-dir)/link_opt.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_drc -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/placed.dcp: $(build-dir)/link_opt.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
#	$(call file-append,$@.tcl,implement_debug_core)
#	$(foreach s,$(all-constraint-sources),$(call file-append_constraint_synth,$@,$s))
	$(call file-append,$@.tcl,place_design)
	$(call file-append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/placed_io.rpt: $(build-dir)/placed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_io -file $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/placed_usage.rpt: $(build-dir)/placed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_utilization -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/placed_control_sets.rpt: $(build-dir)/placed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_control_sets -verbose -file $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed.dcp: $(build-dir)/placed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,route_design)
	$(call file-append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_drc.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_drc -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_methodology.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_methodology -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_power.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_power -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_route_status.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_route_status -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_timing_summary.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_timing_summary -max_paths 10 -file $(notdir $@) -rpx $(notdir $(@:.rpt=.rpx)) -warn_on_violation)
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_incremental_reuse.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_incremental_reuse -file $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/routed_clock_utilization.rpt: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,report_clock_utilization -file $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/bitstream.bit: $(build-dir)/routed.dcp
	$(call file-clear,$@.tcl)
	$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call file-append,$@.tcl,write_bitstream -force $(notdir $@))
	$(call vivado-tcl-run,$@.tcl)

$(build-dir)/$(target)-fast.tcl: $(build-dir)/sources.tcl $(vivado-init-tcl) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call project_init,$@)
	$(call file-append,$@,source sources.tcl)
	$(call file-append,$@,foreach {ip} [get_ips] {)
	$(call file-append,$@,    generate_target "synthesis implementation" $$ip)
	$(call file-append,$@,    synth_ip $$ip)
	$(call file-append,$@,})
	$(call file-append,$@,synth_design -top $(top-entity) -part $(target_part)$(target_package)$(target_speed) -assert)
	$(call file-append,$@,opt_design)
	$(call file-append,$@,place_design)
	$(call file-append,$@,route_design)
	$(call file-append,$@,report_route_status -file route_status.rpt)
	$(call file-append,$@,report_timing_summary -file timing_summary.rpt)
	$(call file-append,$@,report_power -file power.rpt)
	$(call file-append,$@,report_utilization -file utilization.rpt)
	$(call file-append,$@,write_edif -force $(top-entity).edif)
	$(call file-append,$@,report_drc -file drc.rpt)
	$(call file-append,$@,write_bitstream -force ../$(notdir $(@:.tcl=.bit)))

$(target)-fast.bit: $(build-dir)/$(target)-fast.tcl
	$(call vivado-tcl-run,$<)

$(target)-fast.x1.mcs: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format MCS -interface SPIx1 -loadbit "up 0x0 $<" $@)

$(target)-fast.x2.mcs: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format MCS -interface SPIx2 -loadbit "up 0x0 $<" $@)

$(target)-fast.x4.mcs: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format MCS -interface SPIx4 -loadbit "up 0x0 $<" $@)

$(target)-fast.x1.bin: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format BIN -interface SPIx1 -loadbit "up 0x0 $<" $@)

$(target)-fast.x2.bin: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format BIN -interface SPIx2 -loadbit "up 0x0 $<" $@)

$(target)-fast.x4.bin: $(target)-fast.bit
	$(call vivado-tcl-cmd,write_cfgmem -force -size 16 -format BIN -interface SPIx4 -loadbit "up 0x0 $<" $@)

clean-dirs += $(build-dir)
