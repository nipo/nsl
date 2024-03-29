ICECUBE2 = /opt/Lattice/iCEcube2.2017.08
SBT = $(ICECUBE2)/sbt_backend
SBT_OPT_BIN = $(SBT)/bin/linux/opt
SBT_OPT_LIB = $(SBT)/lib/linux/opt
DEVICES_DIR = $(SBT)/devices
SYNTHESIS_TOOL ?= synplify

#$(call exclude-libs,sb_ice)

include $(BUILD_ROOT)/tool/icecube-devices.mk

target_dev := $(DEVICES_DIR)/$(call ice-resolve-name,dev,$(target_part),$(target_package),$(target_speed))
target_lib := $(DEVICES_DIR)/$(call ice-resolve-name,lib,$(target_part),$(target_package),$(target_speed))

empty :=
space := $(empty) $(empty)
comma := ,

define ICECUBE2_PREPARE
LD_LIBRARY_PATH=$(SBT_OPT_BIN)/synpwrap:$(SBT_OPT_LIB) \
SYNPLIFY_PATH=$(ICECUBE2)/synpbase \
TCL_LIBRARY=$(SBT)/bin/linux/lib/tcl8.4
endef

target ?= $(top)

SHELL=/bin/bash

all: $(target).bin $(target).tar

define syn-add-vhdl
	$(SILENT)echo 'add_file -$($1-language) -lib $($1-library) "$1"' >> $(build-dir)/synth.prj

endef

define syn-add-verilog
	$(SILENT)echo 'add_file -$($1-language) -lib $($1-library) "$1"' >> $(build-dir)/synth.prj

endef

define syn-add-constraint
	$(SILENT)echo '$(if $(filter %.pcf,$1),# ,)add_file -$($1-language) "$1"' >> $(build-dir)/synth.prj

endef

# Synthesis
# Generate synplify input project
# Run synplify
# Converting result EDIF to SDC
$(build-dir)/synth/$(target).sdc: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $(build-dir)/synth.prj
	$(foreach s,$(sources),$(call syn-add-$($s-language),$s))
	$(SILENT)echo "impl -add synth -type fpga" >> $(build-dir)/synth.prj
#	$(SILENT)echo "set_option -vhdl2008 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -technology SBTiCE40" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -part $(target_part)" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -package $(target_package)" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -speed_grade $(target_speed)" >> $(build-dir)/synth.prj
#	$(SILENT)echo "set_option -speed_part_companion \"\"" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -top_module $(top-lib).$(top-entity)" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -frequency auto" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -write_verilog 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -write_vhdl 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -maxfan 10000" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -disable_io_insertion 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -pipe 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -retiming 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -update_models_cp 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -fixgatedclocks 2" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -fixgeneratedclocks 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -popfeed 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -constprop 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -createhierarchy 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -symbolic_fsm_compiler 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -compiler_compatible 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -resource_sharing 0" >> $(build-dir)/synth.prj
	$(SILENT)echo "set_option -write_apr_constraint 1" >> $(build-dir)/synth.prj
	$(SILENT)echo "project -result_format edif" >> $(build-dir)/synth.prj
	$(SILENT)echo "project -result_file synth/$(notdir $@)" >> $(build-dir)/synth.prj
	$(SILENT)echo "project -log_file \"synth.log\"" >> $(build-dir)/synth.prj
	$(SILENT)echo "impl -active synth" >> $(build-dir)/synth.prj
	$(SILENT)echo "project -run synthesis -clean" >> $(build-dir)/synth.prj
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/synpwrap/synpwrap \
		-prj $(build-dir)/synth.prj || (cat $(build-dir)/synth.log ; exit 1)
	$(SILENT)cat $(build-dir)/synth.log
	$(SILENT)mkdir -p $(build-dir)/synth/oadb-$(top-entity)
	cat $(filter %.pcf,$(sources)) < /dev/null > $(build-dir)/synth/phys_constraints.pcf
	$(SILENT)$(ICECUBE2_PREPARE) \
	$(SBT_OPT_BIN)/edifparser \
		$(target_dev) \
		$(build-dir)/synth/$(target).edf \
		$(build-dir)/synth \
		-p$(target_package) \
		-y$(build-dir)/synth/phys_constraints.pcf \
		-c \
		--devicename $(target_part)
	$(SILENT)> $@
	$(SILENT)if [ -e $(build-dir)/synth/AutoConstraint_$(top-entity).sdc ] ; then \
		cat $(build-dir)/synth/AutoConstraint_$(top-entity).sdc >> $@ ; \
	else if [ -e $(build-dir)/Temp/sbt_temp.sdc ] ; then \
		cat $(build-dir)/Temp/sbt_temp.sdc >> $@ ; \
	fi ; \
	fi
	-bash $(BUILD_ROOT)/support/synplify_sdc_gen $(build-dir)/Temp/sbt_temp.sdc $(build-dir)/synth/$(target).edf >> $@

clean-dirs += $(build-dir)

# Place with constraints
$(build-dir)/placed/$(target).sdc: $(build-dir)/synth/$(target).sdc
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)$(ICECUBE2_PREPARE) \
	$(SBT_OPT_BIN)/sbtplacer \
		--des-lib $(build-dir)/synth/oadb-$(top-entity) \
		--outdir $(build-dir)/placed \
		--device-file $(target_dev) \
		--package $(target_package) \
		--deviceMarketName $(target_part) \
		--sdc-file $< \
		--lib-file $(target_lib) \
		--effort_level std \
		--out-sdc-file $@

# Router
# Pack router input file
# Route resulting file
$(build-dir)/routed/$(target).sdc: $(build-dir)/placed/$(target).sdc
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)mkdir -p $(dir $@)packed
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/packer \
		$(target_dev) \
		$(build-dir)/synth/oadb-$(top-entity) \
		--package $(target_package) \
		--outdir $(dir $@). \
		--translator $(SBT)/bin/sdc_translator.tcl \
		--src_sdc_file $< \
		--dst_sdc_file $(dir $@)packed/$(notdir $@) \
		--devicename $(target_part)
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/sbrouter \
		$(target_dev) \
		$(build-dir)/synth/oadb-$(top-entity) \
		$(target_lib) \
		$(dir $@)packed/$(notdir $@) \
		--outdir $(dir $@). \
		--sdf_file $(dir $@)routed.sdf \
		--pin_permutation
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/netlister \
		--lib $(build-dir)/synth/oadb-$(top-entity) \
		--verilog $(@:.sdc=.v) \
		--vhdl $(@:.sdc=.vhd) \
		--view rt \
		--device $(target_dev) \
		--splitio \
		--in-sdc-file $(dir $@)packed/$(notdir $@) \
		--out-sdc-file $@
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/sbtimer \
		--des-lib $(build-dir)/synth/oadb-$(top-entity) \
		--lib-file $(target_lib) \
		--sdc-file $@ \
		--sdf-file $(dir $@)routed.sdf \
		--report-file $(dir $@)timing.rpt \
		--device-file $(target_dev) \
		--timing-summary

# Bitstream
$(build-dir)/$(top-entity)_bitmap.bin \
$(build-dir)/$(top-entity)_bitmap.hex \
$(build-dir)/$(top-entity)_bitmap.nvcm : $(build-dir)/routed/$(target).sdc
	$(SILENT)$(ICECUBE2_PREPARE) \
		$(SBT_OPT_BIN)/bitmap \
		$(target_dev) \
		--design $(build-dir)/synth/oadb-$(top-entity) \
		--device_name $(target_part) \
		--package $(target_package) \
		--outdir $(build-dir) \
		--low_power on \
		--init_ram on \
		--init_ram_bank 1111 \
		--frequency low \
		--warm_boot on

$(target).%: $(build-dir)/$(top-entity)_bitmap.%
	cp $< $@

$(target).tar: $(build-dir)
	tar -C $(build-dir) -cf $@ .

clean-files += stdout.log
clean-files += stdout.log.bak
clean-files += synlog.tcl
clean-files += $(target).bin
clean-files += $(target).hex
clean-files += $(target).nvcm
clean-files += $(top-entity)_bitmap.bin
clean-files += $(top-entity)_bitmap.hex
clean-files += $(top-entity)_bitmap.nvcm
clean-files += $(top-entity)_bitmap_glb.txt
clean-files += $(top-entity)_bitmap_int.hex
