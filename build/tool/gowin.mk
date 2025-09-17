GOWIN = /opt/Gowin/V1.9.8.08
GOWIN_BIN = $(GOWIN)/IDE/bin
PROGRAMMER_BIN = $(GOWIN)/Programmer/bin
DEVICE_INFO=$(GOWIN)/IDE/data/device/device_info.csv
c:=,
user_id := $(shell python3 -c 'import random ; print(f"{random.randint(0, 1<<32):x}")')
gowin-use-as-gpio ?=

target-klut := $(shell grep "$(target_part)" "$(DEVICE_INFO)" | head -n 1 | cut -d, -f4 | sed 'sxGW.*T-\([0-9]\+\).*x\1x')

target ?= $(top)

SHELL=/bin/bash

define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define _gowin-project-add-vhdl
	$(call file-append,$1,add_file -type vhdl {$2})
	$(call file-append,$1,set_file_prop -lib {$($2-library)} {$2})

endef

define _gowin-project-add-verilog
	$(call file-append,$1,add_file -type verilog {$2})
	$(call file-append,$1,set_file_prop -lib {$($2-library)} {$2})

endef

define _gowin-project-sdc-sdc
	$(call file-append,$1,exec sh $(BUILD_ROOT)/support/gowin_sdc_append.sh $2 $(build-dir)/all.sdc)

endef

define _gowin-cst-add-constraint
	$(SILENT)echo "# From $2" >> $1
	$(SILENT)cat $2 >> $1
	$(SILENT)echo "" >> $1

endef

$(build-dir)/all.cst: $(all-constraint-sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(foreach s,$(sources),$(call _gowin-cst-add-$($s-language),$@,$s))

# Generate batch build command
$(build-dir)/$(target).tcl: $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,set_device -name $(target_part_name) $(target_part))
	$(call file-append,$@,add_file -type vhdl {$(BUILD_ROOT)/support/ieee/math_real.pkg.vhd})
	$(call file-append,$@,set_file_prop -lib {ieee} {$(BUILD_ROOT)/support/ieee/math_real.pkg.vhd})
	$(call file-append,$@,add_file -type vhdl {$(BUILD_ROOT)/support/ieee/math_real-body.vhd})
	$(call file-append,$@,set_file_prop -lib {ieee} {$(BUILD_ROOT)/support/ieee/math_real-body.vhd})
	$(foreach s,$(sources),$(call _gowin-project-add-$($s-language),$@,$s))
	$(call file-append,$@,add_file -type cst $(build-dir)/all.cst)
	$(call file-append,$@,add_file -type sdc $(build-dir)/all.sdc)
	$(call file-append,$@,$(if $(all-serdes-config-sources),set_csr {$(build-dir)/computed.csr}))
	$(call file-append,$@,set_option -top_module $(top-entity))
	$(call file-append,$@,set_option -output_base_name $(target))
	$(call file-append,$@,set_option -looplimit 0)
	$(call file-append,$@,set_option -print_all_synthesis_warning 1)
	$(call file-append,$@,set_option -gen_text_timing_rpt 1)
	$(call file-append,$@,set_option -rpt_auto_place_io_info 1)
	$(call file-append,$@,set_option -bit_compress 1)
	$(call file-append,$@,set_option -retiming 1)
	$(call file-append,$@,set_option -gen_vhdl_sim_netlist 1)
	$(call file-append,$@,set_option -gen_text_timing_rpt 1)
	$(call file-append,$@,set_option -user_code {$(user_id)})
	$(foreach u,$(gowin-use-as-gpio),$(call file-append,$@,set_option -use_$u_as_gpio 1))
	$(call file-append,$@,run syn)
	$(call file-append,$@,puts {Generating auto constraints...})
	$(call file-append,$@,exec sh $(BUILD_ROOT)/support/gowin_sdc_auto.sh $(build-dir)/impl/gwsynthesis/$(target).vg $(build-dir)/all.sdc)
	$(foreach s,$(sources),$(call _gowin-project-sdc-$($s-language),$@,$s))
	$(call file-append,$@,run pnr)

$(build-dir)/computed.csr: $(all-serdes-config-sources) /dev/null
	$(GOWIN_BIN)/serdes_toml_to_csr.dist/serdes_toml_to_csr_$(target-klut)k.bin "$<" -o "$@"

$(build-dir)/impl/pnr/$(target).fs: $(build-dir)/$(target).tcl $(sources) $(build-dir)/all.cst $(if $(all-serdes-config-sources),$(build-dir)/computed.csr)
	$(SILENT)cd $(build-dir) && $(GOWIN_BIN)/gw_sh $<

$(target).fs: $(build-dir)/impl/pnr/$(target).fs
	$(SILENT)rm -f $@
	$(SILENT)cp $< $@
	$(SILENT)chmod 644 $@
