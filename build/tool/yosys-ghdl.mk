GHDL=ghdl
GHDL_MODULE=-m /usr/local/lib/ghdl_yosys.so
YOSYS=yosys
target ?= $(top-entity)
GHDL_PRE=
PNR_PRE=
ICESTORM_PRE=

-include local.mk

all: $(target).bin

.PRECIOUS: $(target).bin

.PHONY: FORCE

_GHDL_STD_93=93c
_GHDL_STD_08=08
_GHDL_CF_SUFFIX_93=93
_GHDL_CF_SUFFIX_08=08

clean-dirs += $(build-dir)

define ghdl-library-rules
	$(if $(foreach s,$($1-sources),$(if $(filter $($s-language),vhdl),$s)),$(SILENT)cd $(dir $@) ; $(GHDL) -a --std=$(_GHDL_STD_$($1-vhdl-version)) --work=$1 $(foreach s,$($1-sources),$(if $(filter $($s-language),vhdl),$s)))

endef

$(build-dir)/$(target).json: $(sources) $(MAKEFILE_LIST)
	mkdir -p $(dir $@)
	$(foreach l,$(libraries),$(call ghdl-library-rules,$l))
	$(SILENT)$(GHDL_PRE) bash -c "cd $(PWD)/$(dir $@) ; yosys $(GHDL_MODULE) -p 'ghdl $(top-entity); synth_ice40 -json $(notdir $@)'"

$(build-dir)/$(target).asc: $(build-dir)/$(target).json
	$(SILENT)$(PNR_PRE) bash -c "cd $(PWD)/$(dir $@) ; nextpnr-ice40 --package up5k $(foreach p,$(filter %.pcf,$(sources)),--pcf $p) --asc $(notdir $@) --json $(notdir $<)"

$(build-dir)/$(target).bin: $(build-dir)/$(target).asc
	$(SILENT)$(ICESTORM_PRE) bash -c "cd $(PWD)/$(dir $@) ; icepack $(notdir $<) $(notdir $@)"

$(target).bin: $(build-dir)/$(target).bin
	cp $< $@

clean-files += *.o $(target) $(target).bin *.cf *.lst $(target)
