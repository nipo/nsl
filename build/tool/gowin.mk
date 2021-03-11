GOWIN = /opt/Gowin/1.9.7.01Beta
GOWIN_BIN = $(GOWIN)/IDE/bin
PROGRAMMER_BIN = $(GOWIN)/Programmer/bin

build-dir := gowin-build

target ?= $(top)

SHELL=/bin/bash

define syn-add-vhdl
	$(SILENT)echo 'add_file -type vhdl "$1"' >> $@
	$(SILENT)echo 'set_file_prop -lib $($1-library) "$1"' >> $@

endef

define syn-add-verilog
	$(SILENT)echo 'add_file -type verilog "$1"' >> $@
	$(SILENT)echo 'set_file_prop -lib $($1-library) "$1"' >> $@

endef

define syn-add-xdc
	$(SILENT)echo 'add_file -type xdc "$1"' >> $@

endef

define syn-add-cst
	$(SILENT)echo 'add_file -type cst "$1"' >> $@

endef

# Generate batch build command
$(build-dir)/main.tcl: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(foreach s,$(sources),$(call syn-add-$($s-language),$s))
	$(SILENT)echo "set_option -output_base_name $(target)" >> $@
	$(SILENT)echo "set_option -top_module $(top-entity)" >> $@
	$(SILENT)echo "set_device $(target_part)$(target_package)$(target_speed)" >> $@
	$(SILENT)echo "set_option -retiming 1" >> $@
	$(SILENT)echo "set_option -bit_compress 1" >> $@
	$(SILENT)echo "run all" >> $@

$(build-dir)/impl/pnr/$(target).fs: $(build-dir)/main.tcl
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)cat $< | (cd $(build-dir) ; $(GOWIN_BIN)/gw_sh) | tee $(build-dir)/build.log
	$(SILENT)test -z "$$(grep -l ERROR $(build-dir)/build.log)"

$(target).%: $(build-dir)/impl/pnr/$(target).%
	cp $< $@ && chmod +w $@

programmer-GW1N-LV1 = GW1N-1

program: $(build-dir)/impl/pnr/$(target).fs
	$(PROGRAMMER_BIN)/programmer_cli \
		-d $(programmer-$(target_part)) \
		--cable "Gowin USB Cable(FT2CH)" \
		--channel 0 \
		-r 4 -f $${PWD}/$<
