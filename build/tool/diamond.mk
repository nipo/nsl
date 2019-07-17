DIAMOND_PATH = /usr/local/diamond/3.10_x64
PRE=bindir=$(DIAMOND_PATH)/bin/lin64 . $(DIAMOND_PATH)/bin/lin64/diamond_env && 
DIAMOND_BIN = $(PRE) $(DIAMOND_PATH)/bin/lin64
ISPFPGA_BIN = $(PRE) $(DIAMOND_PATH)/ispfpga/bin/lin64
DIAMOND_LIB_PATH = $(DIAMOND_PATH)/ispfpga/$(target_dir)/data
build-dir := diamond-build

all: $(target).bit

define append
	$(SILENT)echo '$2' >> $1
endef

define syn_hdl_do
	$(call append,$1,add_file -$($2-language) -lib $($2-library) {$2})

endef

define synth_source_do
	$(if $(filter constraint,$($2-language)),,$(call syn_hdl_do,$1,$2))

endef

clean-dirs += $(build-dir)
clean-files += $(target).bit

define synp_proj_opts
	$(call append,$@,impl -add $(subst .prj,,$(notdir $@)) -type fpga)
#	$(call append,$@,set_option -vhdl2008 1)
	$(call append,$@,set_option -technology $(target_technology))
	$(call append,$@,set_option -part $(target_part))
	$(call append,$@,set_option -package $(target_package2))
	$(call append,$@,set_option -speed_grade $(target_speed))
#	$(call append,$@,set_option -speed_part_companion "")
	$(call append,$@,set_option -top_module $(top-lib).$(top-entity))
	$(call append,$@,set_option -frequency auto)
	$(call append,$@,set_option -write_verilog 0)
	$(call append,$@,set_option -write_vhdl 0)
	$(call append,$@,set_option -maxfan 10000)
	$(call append,$@,set_option -disable_io_insertion 0)
	$(call append,$@,set_option -pipe 1)
	$(call append,$@,set_option -retiming 1)
	$(call append,$@,set_option -update_models_cp 0)
#	$(call append,$@,set_option -fixgatedclocks 3)
#	$(call append,$@,set_option -fixgeneratedclocks 3)
	$(call append,$@,set_option -popfeed 0)
	$(call append,$@,set_option -constprop 1)
	$(call append,$@,set_option -createhierarchy 0)
	$(call append,$@,set_option -symbolic_fsm_compiler 1)
	$(call append,$@,set_option -compiler_compatible 0)
	$(call append,$@,set_option -resource_sharing 1)
	$(call append,$@,set_option -write_apr_constraint 1)
	$(call append,$@,project -result_format edif)
	$(call append,$@,project -result_file $(target).edi)
	$(call append,$@,project -log_file "$(subst .prj,.log,$(notdir $@))")
	$(call append,$@,impl -active $(subst .prj,,$(notdir $@)))
	$(call append,$@,project -run synthesis -clean)
endef

$(build-dir)/synth_pre.prj: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,add_file -vhdl {$(DIAMOND_PATH)/cae_library/synthesis/vhdl/machxo2.vhd})
	$(foreach s,$(sources),$(call synth_source_do,$@,$s))
	$(synp_proj_opts)

$(build-dir)/synth_pre/$(target).edi: $(build-dir)/synth_pre.prj
	cd $(build-dir)/ && \
		( $(DIAMOND_BIN)/synpwrap -prj synth_pre.prj ; \
		  exl=$$? ; \
		  sed -f $(BUILD_ROOT)/support/synplify_output_rewrite.sed < synth_pre.log ; \
		  exit $$exl)

$(build-dir)/port_remap.sed: $(build-dir)/synth_pre/$(target).edi
	grep "^top port" $(build-dir)/synth_pre/.recordref | \
		sed -e 's:top port \(.*\) \(.*\):s,\1,\2,:' > $@

$(build-dir)/remapped.sdc: $(filter %.sdc,$(all-constraint-sources)) $(build-dir)/port_remap.sed
	cat $(filter %.sdc,$^) /dev/null | sed -f $(build-dir)/port_remap.sed > $@

$(build-dir)/synth.prj: $(sources) $(build-dir)/remapped.sdc $(BUILD_ROOT)/support/generic_timing_constraints_synplify.tcl $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,add_file -vhdl {$(DIAMOND_PATH)/cae_library/synthesis/vhdl/machxo2.vhd})
	$(foreach s,$(sources),$(call synth_source_do,$@,$s))
	$(call append,$@,add_file -constraint {remapped.sdc})
	$(call append,$@,add_file -constraint {$(BUILD_ROOT)/support/generic_timing_constraints_synplify.tcl})
	$(foreach s,$(filter %.tcl,$(all-constraint-sources)),$(call append,$@,add_file -constraint {$s}))
	$(synp_proj_opts)

$(build-dir)/synth/$(target).edi: $(build-dir)/synth.prj
	cd $(build-dir)/ && \
		( $(DIAMOND_BIN)/synpwrap -prj synth.prj ; \
		  exl=$$? ; \
		  sed -f $(BUILD_ROOT)/support/synplify_output_rewrite.sed < synth.log ; \
		  exit $$exl)

$(build-dir)/post_synth/$(target).ngo: $(build-dir)/synth/$(target).edi
	@mkdir -p $(dir $@)
	cd $(build-dir) && $(ISPFPGA_BIN)/edif2ngd \
		-l $(target_arch) -d $(subst _,-,$(target_part)) \
		synth/$(target).edi post_synth/$(target).ngo

$(build-dir)/post_synth/$(target).ngd: $(build-dir)/post_synth/$(target).ngo
	@mkdir -p $(dir $@)
	cd $(build-dir) && $(ISPFPGA_BIN)/ngdbuild \
		-a $(target_arch) -d $(subst _,-,$(target_part)) \
		-p $(DIAMOND_PATH)/ispfpga/$(target_dir)/data \
		post_synth/$(target).ngo post_synth/$(target).ngd

$(build-dir)/constraints.lpf: $(all-constraint-sources) $(build-dir)/port_remap.sed
	cat $(filter %.lpf,$(all-constraint-sources)) | sed -f $(build-dir)/port_remap.sed > $@

$(build-dir)/map/$(target).ncd: $(build-dir)/post_synth/$(target).ngd $(build-dir)/constraints.lpf
	@mkdir -p $(dir $@)
	cd $(build-dir) && $(ISPFPGA_BIN)/map \
		-a $(target_arch) -p $(subst _,-,$(target_part)) -t $(target_package2) -s $(subst -,,$(target_speed)) \
		-oc Commercial \
		post_synth/$(target).ngd -o map/$(target).ncd \
		-pr $(target).prf -mp $(target).mrp \
		constraints.lpf

$(build-dir)/$(target).par.cfg:
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,-w)
	$(call append,$@,-l 5)
	$(call append,$@,-i 6)
	$(call append,$@,-n 1)
	$(call append,$@,-t 1)
	$(call append,$@,-s 1)
	$(call append,$@,-c 2)
	$(call append,$@,-e 0)
	$(call append,$@,-exp parUseNBR=0:parCDP=0:parCDR=0:parPathBased=ON:parMultiSeedSortMode=timingScore)

$(build-dir)/$(target).p3t:
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,-rem)
	$(call append,$@,-distrce)
	$(call append,$@,-log "$(target)_p3t.log")
	$(call append,$@,-o "$(target).csv")
	$(call append,$@,-pr "$(target).prf")

$(build-dir)/$(target).t2b:
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,-g RamCfg:Reset)
	$(call append,$@,-path "$(realpath $(build-dir))")

$(build-dir)/mpartrce/$(target).ncd: $(build-dir)/map/$(target).ncd $(build-dir)/$(target).par.cfg $(build-dir)/$(target).p3t
	@mkdir -p $(dir $@)
	cd $(build-dir) && $(DIAMOND_BIN)/mpartrce \
		-p $(target).par.cfg -f $(target).p3t \
		-tf $(target).pt map/$(target).ncd \
		mpartrce/$(target).ncd

$(build-dir)/par/$(target).ncd: $(build-dir)/map/$(target).ncd $(build-dir)/$(target).par.cfg
	@mkdir -p $(dir $@)
	cd $(build-dir) && $(ISPFPGA_BIN)/par \
		-f $(target).par.cfg map/$(target).ncd \
		par/$(target) $(target).prf
#	cd $(build-dir) && $(ISPFPGA_BIN)/ltxt2ptxt -path . $(target).ncd

$(build-dir)/$(target).jed: $(build-dir)/par/$(target).ncd $(build-dir)/$(target).t2b
	cd $(build-dir) && $(ISPFPGA_BIN)/bitgen \
		-w par/$(target).ncd -f $(target).t2b \
		-jedec $(target).jed

$(target).bit: $(build-dir)/$(target).jed
	cd $(build-dir) && $(DIAMOND_BIN)/ddtcmd -oft \
		-bit -if $(target).jed -compress off \
		-config_mode jtag -of ../$@ -dev $(subst _,-,$(target_part))

$(target)-compressed.bit: $(build-dir)/$(target).jed
	cd $(build-dir) && $(DIAMOND_BIN)/ddtcmd -oft \
		-bit -if $(target).jed -compress on \
		-header -of ../$@ -dev $(subst _,-,$(target_part))

%-ram.svf: %.bit
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "SRAM Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(subst _,-,$(target_part))
#	sed -i 's:RUNTEST.*IDLE.*;:RUNTEST IDLE 32 TCK;:' $@

%-flash.svf: $(build-dir)/$(target).jed
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "FLASH Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(subst _,-,$(target_part))
#	sed -i 's:RUNTEST.*IDLE.*10002.*TCK;:RUNTEST IDLE 32 TCK;:' $@
#	sed -i 's:RUNTEST.*IDLE.*15000002.*TCK;:RUNTEST IDLE 100 TCK 0.8E-00 SEC;:' $@

%-compressed-flash.svf: $(build-dir)/$(target).jed
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "FLASH Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(subst _,-,$(target_part))
#	sed -i 's:RUNTEST.*IDLE.*10002.*TCK;:RUNTEST IDLE 32 TCK;:' $@
#	sed -i 's:RUNTEST.*IDLE.*15000002.*TCK;:RUNTEST IDLE 100 TCK 0.8E-00 SEC;:' $@
