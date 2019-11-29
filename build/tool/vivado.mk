VIVADO = /opt/Xilinx/Vivado/2017.4
VIVADO_PREPARE = source $(VIVADO)/settings64.sh > /dev/null

SHELL=/bin/bash

build-dir := vivado-build
vivado-run = $(SILENT)$(VIVADO_PREPARE) ; cd $(dir $1) ; vivado -mode batch -source $(notdir $1)

source-types += dcp

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

sources += $(BUILD_ROOT)/support/generic_timing_constraints_vivado.tcl
$(BUILD_ROOT)/support/generic_timing_constraints_vivado.tcl-language = constraint
all-constraint-sources += $(BUILD_ROOT)/support/generic_timing_constraints_vivado.tcl

all: $(target).bit

$(target).bit: $(build-dir)/bitstream.bit
	cp $< $@

define append
	$(SILENT)echo '$2' >> $1
endef

define append_vhdl_synth
	$(call append,$1,read_vhdl -library $($2-library) $2)

endef

define append_verilog_synth
	$(call append,$1,read_verilog -library $($2-library) $2)

endef

define append_constraint_synth
	$(if $(filter %.xdc,$2),$(call append,$1,read_xdc $2))	

endef

define append_bd_synth
	$(call append,$1,catch {add_files $2})
	$(call append,$1,reset_target Synthesis [get_files $2])
	$(call append,$1,open_bd_design $2)
	$(call append,$1,write_bd_tcl debug.tcl)
	$(call append,$1,exit)
	$(call append,$1,update_compile_order)
endef
#	$(call append,$1,generate_target Synthesis [get_files $2])
#	$(call append,$1,read_vhdl -library $($2-library) $(dir $2)/hdl/$(patsubst %.bd,%.vhd,$(notdir $2)))

define append_xci_synth
	$(call append,$1,read_ip -quiet $2)

endef

append_xci_link=$(value append_xci_synth)

define append_dcp_link
	$(call append,$1,add_files -quiet $2)

endef

define append_dcp_link
# WTF

endef

define read_checkpoint
	$(foreach s,$(sources),$(call append_$($s-language)_link,$1,$s))
	$(call append,$1,link_design -top $(top-entity) -part $(target_part)$(target_package)$(target_speed))
	$(call append,$1,open_checkpoint -quiet $2)

endef

define tcl_init
	mkdir -p $(dir $1)
	$(SILENT)> $1
endef

define project_init
	$(call append,$1,create_project -in_memory -part $(target_part)$(target_package)$(target_speed))
	$(SILENT)for f in $(vivado-init-tcl) ; do \
		cat $$f >> $1 ; \
	done
endef

# 	$(call append,$1,set_param project.singleFileAddWarning.threshold 0)
# 	$(call append,$1,set_param project.compositeFile.enableAutoGeneration 0)
# 	$(call append,$1,set_param synth.vivado.isSynthRun true)
# 	$(call append,$1,set_property webtalk.parent_dir $(realpath $(dir $1))/wt [current_project])
# 	$(call append,$1,set_property default_lib work [current_project])
# 	$(call append,$1,set_property target_language VHDL [current_project])
# #	$(call append,$1,set_property ip_repo_paths {IP REPO PATHS} [current_project])
# 	$(call append,$1,set_property ip_output_repo $(realpath $(dir $1))/ip [current_project])
# 	$(call append,$1,set_property ip_cache_permissions {read write} [current_project])

define project_load_sources
	$(foreach s,$(sources),$(call append_$($s-language)_synth,$1,$s))

	$(call append,$1,foreach dcp [get_files -quiet -all -filter file_type=="Design\ Checkpoint"] {)
	$(call append,$1,  set_property used_in_implementation false $$dcp)
	$(call append,$1,})

endef

project/$(top).xpr: $(sources) $(vivado-init-tcl) $(MAKEFILE_LIST)
	mkdir -p project
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(SILENT)$(call project_load_sources,$@.tcl)
	$(call append,$@.tcl,save_project_as -force $(top) ../$(dir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/synth.dcp: $(sources) $(vivado-init-tcl) $(MAKEFILE_LIST)
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(SILENT)$(call project_load_sources,$@.tcl)
	$(call append,$@.tcl,synth_design -top $(top-entity) -part $(target_part)$(target_package)$(target_speed))
	$(call append,$@.tcl,write_checkpoint -force -noxdef $(notdir $@))
	$(call vivado-run,$@.tcl)

#	$(call append,$@.tcl,set_param constraints.enableBinaryConstraints false)

$(build-dir)/synth.rpt: $(build-dir)/synth.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_utilization -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-run,$@.tcl)

$(build-dir)/link_opt.dcp: $(build-dir)/synth.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,opt_design)
	$(call append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/link_opt_drc.rpt: $(build-dir)/link_opt.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_drc -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-run,$@.tcl)

$(build-dir)/placed.dcp: $(build-dir)/link_opt.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
#	$(call append,$@.tcl,implement_debug_core)
	$(foreach s,$(all-constraint-sources),$(call append_constraint_synth,$@,$s))
	$(call append,$@.tcl,place_design)
	$(call append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/placed_io.rpt: $(build-dir)/placed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_io -file $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/placed_usage.rpt: $(build-dir)/placed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_utilization -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-run,$@.tcl)

$(build-dir)/placed_control_sets.rpt: $(build-dir)/placed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_control_sets -verbose -file $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed.dcp: $(build-dir)/placed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,route_design)
	$(call append,$@.tcl,write_checkpoint -force $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_drc.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_drc -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_methodology.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_methodology -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_power.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_power -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)) -rpx $(notdir $(@:.rpt=.rpx)))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_route_status.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_route_status -file $(notdir $@) -pb $(notdir $(@:.rpt=.pb)))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_timing_summary.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_timing_summary -max_paths 10 -file $(notdir $@) -rpx $(notdir $(@:.rpt=.rpx)) -warn_on_violation)
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_incremental_reuse.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_incremental_reuse -file $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/routed_clock_utilization.rpt: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,report_clock_utilization -file $(notdir $@))
	$(call vivado-run,$@.tcl)

$(build-dir)/bitstream.bit: $(build-dir)/routed.dcp
	$(call tcl_init,$@.tcl)
	$(SILENT)$(call project_init,$@.tcl)
	$(call read_checkpoint,$@.tcl,$(notdir $<))
	$(call append,$@.tcl,write_bitstream -force $(notdir $@))
	$(call vivado-run,$@.tcl)

clean-dirs += $(build-dir)
