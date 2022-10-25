GOWIN = /opt/Gowin/V1.9.8.08
GOWIN_BIN = $(GOWIN)/IDE/bin
PROGRAMMER_BIN = $(GOWIN)/Programmer/bin
DEVICE_INFO=$(GOWIN)/IDE/data/device/device_info.csv
c:=,
user_id := $(shell python3 -c 'import random ; print(f"{random.randint(0, 1<<32):x}")')
gowin-use-as-gpio ?=

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

define _gowin-project-add-constraint
	$(call file-append,$1,add_file -type cst {$2})

endef

define _gowin-project-add-sdc
	$(call file-append,$1,add_file -type sdc {$2})

endef

# Generate batch build command
$(build-dir)/$(target).tcl: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,set_device -name $(target_part_name) $(target_part))
	$(call file-append,$@,add_file -type vhdl {$(BUILD_ROOT)/support/ieee/math_real.pkg.vhd})
	$(call file-append,$@,set_file_prop -lib {ieee} {$(BUILD_ROOT)/support/ieee/math_real.pkg.vhd})
	$(call file-append,$@,add_file -type vhdl {$(BUILD_ROOT)/support/ieee/math_real-body.vhd})
	$(call file-append,$@,set_file_prop -lib {ieee} {$(BUILD_ROOT)/support/ieee/math_real-body.vhd})
	$(foreach s,$(sources),$(call _gowin-project-add-$($s-language),$@,$s))
	$(call file-append,$@,set_option -top_module $(top-entity))
	$(call file-append,$@,set_option -output_base_name $(target))
	$(call file-append,$@,set_option -print_all_synthesis_warning 1)
	$(call file-append,$@,set_option -gen_text_timing_rpt 1)
	$(call file-append,$@,set_option -rpt_auto_place_io_info 1)
	$(call file-append,$@,set_option -bit_compress 1)
	$(call file-append,$@,set_option -user_code {$(user_id)})
	$(foreach u,$(gowin-use-as-gpio),$(call file-append,$@,set_option -use_$u_as_gpio 1))
	$(call file-append,$@,run all)

$(build-dir)/impl/pnr/$(target).fs: $(build-dir)/$(target).tcl
	$(SILENT)cd $(build-dir) && $(GOWIN_BIN)/gw_sh $<

$(target).fs: $(build-dir)/impl/pnr/$(target).fs
	$(SILENT)rm -f $@
	$(SILENT)cp $< $@
	$(SILENT)chmod 644 $@
