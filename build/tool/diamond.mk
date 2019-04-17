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

define syn_source_do
	$(call append,$1,add_file -$($2-language) -lib $($2-library) "$2")

endef

$(build-dir)/synth.prj: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(foreach s,$(sources),$(call syn_source_do,$@,$s))
	$(call append,$@,impl -add synth -type fpga)
#	$(call append,$@,set_option -vhdl2008 1)
	$(call append,$@,set_option -technology $(target_technology))
	$(call append,$@,set_option -part $(target_part))
	$(call append,$@,set_option -package $(target_package))
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
	$(call append,$@,project -log_file "synth.log")
	$(call append,$@,impl -active synth)
	$(call append,$@,project -run synthesis -clean)

$(build-dir)/synth/$(target).edi: $(build-dir)/synth.prj
	cd $(build-dir)/ && $(DIAMOND_BIN)/synpwrap -prj synth.prj

$(build-dir)/$(target).ngo: $(build-dir)/synth/$(target).edi
	cd $(build-dir) && $(ISPFPGA_BIN)/edif2ngd \
		-l $(target_tech) -d $(target_part) \
		synth/$(target).edi $(target).ngo

$(build-dir)/$(target).ngd: $(build-dir)/$(target).ngo
	cd $(build-dir) && $(ISPFPGA_BIN)/ngdbuild \
		-a $(target_arch) -d $(target_part) \
		-p $(DIAMOND_PATH)/ispfpga/$(target_dir)/data \
		$(target).ngo $(target).ngd

$(build-dir)/port_remap.sed: $(build-dir)/synth/$(target).edi
	grep "^top port" $(build-dir)/synth/.recordref | \
		sed -e 's:top port \(.*\) \(.*\):s,\1,\2,:' > $@

$(build-dir)/constraints.lpf: $(constraints) $(build-dir)/port_remap.sed
	cat $(constraints) | sed -f $(build-dir)/port_remap.sed > $@

$(build-dir)/$(target)_map.ncd: $(build-dir)/$(target).ngd $(build-dir)/constraints.lpf
	cd $(build-dir) && $(ISPFPGA_BIN)/map \
		-a $(target_arch) -p $(target_part) -t $(target_package) -s $(target_speed) \
		-oc Commercial \
		$(target).ngd -o $(target)_map.ncd \
		-pr $(target).prf -mp $(target).mrp \
		constraints.lpf

$(build-dir)/$(target).p2t:
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
	$(call append,$@,-log "$(target).log")
	$(call append,$@,-o "$(target).csv")
	$(call append,$@,-pr "$(target).prf")

$(build-dir)/$(target).t2b:
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(call append,$@,-g RamCfg:Reset)
	$(call append,$@,-path "$(realpath $(build-dir))")

$(build-dir)/$(target).ncd: $(build-dir)/$(target)_map.ncd $(build-dir)/$(target).p2t $(build-dir)/$(target).p3t
	cd $(build-dir) && $(DIAMOND_BIN)/mpartrce \
		-p $(target).p2t -f $(target).p3t \
		-tf $(target).pt $(target)_map.ncd \
		$(target).ncd

$(build-dir)/$(target).prf: $(build-dir)/$(target).ncd $(build-dir)/$(target).p2t
	cd $(build-dir) && $(ISPFPGA_BIN)/par \
		-f $(target).p2t $(target)_map.ncd \
		$(target).dir $(target).prf
#	cd $(build-dir) && $(ISPFPGA_BIN)/ltxt2ptxt -path . $(target).ncd

$(build-dir)/$(target).jed: $(build-dir)/$(target).prf $(build-dir)/$(target).t2b
	cd $(build-dir) && $(ISPFPGA_BIN)/bitgen \
		-w $(target).ncd -f $(target).t2b \
		-jedec $(target).jed

$(target).bit: $(build-dir)/$(target).jed
	cd $(build-dir) && $(DIAMOND_BIN)/ddtcmd -oft \
		-bit -if $(target).jed -compress off \
		-header -mirror -of ../$@ -dev $(target_part)

$(target)-compressed.bit: $(build-dir)/$(target).jed
	cd $(build-dir) && $(DIAMOND_BIN)/ddtcmd -oft \
		-bit -if $(target).jed -compress on \
		-header -mirror -of ../$@ -dev $(target_part)

%-ram.svf: %.bit
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "SRAM Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(target_part)
#	sed -i 's:RUNTEST.*IDLE.*;:RUNTEST IDLE 32 TCK;:' $@

%-flash.svf: $(build-dir)/$(target).jed
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "FLASH Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(target_part)
#	sed -i 's:RUNTEST.*IDLE.*10002.*TCK;:RUNTEST IDLE 32 TCK;:' $@
#	sed -i 's:RUNTEST.*IDLE.*15000002.*TCK;:RUNTEST IDLE 100 TCK 0.8E-00 SEC;:' $@

%-compressed-flash.svf: $(build-dir)/$(target).jed
	$(DIAMOND_BIN)/ddtcmd -oft -svf \
		-if $< -op "FLASH Erase,Program,Verify" -revd -runtest \
		-of $@ -dev $(target_part)
#	sed -i 's:RUNTEST.*IDLE.*10002.*TCK;:RUNTEST IDLE 32 TCK;:' $@
#	sed -i 's:RUNTEST.*IDLE.*15000002.*TCK;:RUNTEST IDLE 100 TCK 0.8E-00 SEC;:' $@
