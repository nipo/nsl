GOWIN = /opt/Gowin/V1.9.8.03
GOWIN_BIN = $(GOWIN)/IDE/bin
PROGRAMMER_BIN = $(GOWIN)/Programmer/bin
DEVICE_INFO=$(GOWIN)/IDE/data/device/device_info.csv
c:=,
internal-pn:=$(shell grep "^[^,]*,$(target_part),[^,]*,$(target_part_name)" $(DEVICE_INFO) | head -n 1 | cut -d$c -f1)

ifeq ($(internal-pn),)
$(info Close to $(target_part):)
$(info $(shell grep "^[^,]*,$(target_part)" $(DEVICE_INFO) | cut -d$c -f2 | sort -u))
$(error $(target_part) not found)
endif

target ?= $(top)

SHELL=/bin/bash

define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define _gowin-project-header
	$(call file-append,$1,<?xml version="1" encoding="UTF-8"?>)
	$(call file-append,$1,<!DOCTYPE gowin-fpga-project>)
	$(call file-append,$1,<Project>)
	$(call file-append,$1,    <Template>FPGA</Template>)
	$(call file-append,$1,    <Version>5</Version>)
	$(call file-append,$1,    <Device name="" pn="">$2</Device>)
	$(call file-append,$1,    <FileList>)

endef

define _gowin-project-footer
	$(call file-append,$1,    </FileList>)
	$(call file-append,$1,</Project>)

endef

define _gowin-project-add-vhdl
	$(call file-append,$1,        <File path="$2" type="file.vhdl" enable="1" library="$($2-library)"/>)

endef

define _gowin-project-add-cst
	$(call file-append,$1,        <File path="$2" type="file.cst" enable="1"/>)

endef

define _gowin-project-add-constraint
	$(call file-append,$1,        <File path="$2" type="file.cst" enable="1"/>)

endef

define _gowin-project-add-sdc
	$(call file-append,$1,        <File path="$2" type="file.sdc" enable="1"/>)

endef

# Generate batch build command
$(build-dir)/$(target).gprj: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call _gowin-project-header,$@,$(internal-pn))
	$(call file-append,$@,        <File path="$(BUILD_ROOT)/support/ieee/math_real.pkg.vhd" type="file.vhdl" enable="1" library="ieee"/>)
	$(call file-append,$@,        <File path="$(BUILD_ROOT)/support/ieee/math_real-body.vhd" type="file.vhdl" enable="1" library="ieee"/>)
	$(foreach s,$(sources),$(call _gowin-project-add-$($s-language),$@,$s))
	$(call _gowin-project-footer,$@)

$(build-dir)/impl/project_process_config.json: $(BUILD_ROOT)/support/gowin_project_process_config.json $(build-dir)/$(target).config
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)sed -f $(build-dir)/$(target).config < $< > $@

$(build-dir)/$(target).config: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,s:__BASE_NAME__:$(target):g)
	$(call file-append,$@,s:__TOP_MODULE__:$(top-entity):g)
	$(foreach u,$(gowin-use-as-gpio),$(call file-append,$@,s:__USE_$u_AS_GPIO__:true:g))
	$(foreach u,$(gpio-overrides),$(call file-append,$@,s:__USE_$u_AS_GPIO__:false:g))

$(target).fs: $(build-dir)/$(target).gprj $(build-dir)/impl/project_process_config.json
	@
