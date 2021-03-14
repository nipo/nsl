GHDL=ghdl
YOSYS=yosys
YOSYS-GHDL=
target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

GHDL_LLVM :=

_GHDL_STD_93=93c
_GHDL_STD_08=08
_GHDL_CF_SUFFIX_93=93
_GHDL_CF_SUFFIX_08=08

lib_cf = $(call workdir,$1)/$1-obj$(_GHDL_CF_SUFFIX_$($1-vhdl-version)).cf

clean-dirs += ghdl-build
workdir = ghdl-build/$1
ghdl-library-analyze-rules :=

define ghdl-library-rules
	echo Compiling $(l)
	$(SILENT)mkdir -p $(call workdir,$1)
	$(SILENT)$(GHDL) -i \
		--workdir=$(call workdir,$1) \
		$(sort $(foreach l,$($1-libdeps-unsorted),-P$(call workdir,$l))) \
		--std=$(_GHDL_STD_$($1-vhdl-version)) \
		$($l-ghdl-flags) \
		--work=$1 \
		$(foreach f,$($1-sources),$(if $(filter vhdl,$($f-language)),$f))
$(call ghdl-library-analyze-rules,$1)

endef

define ghdl-analyze
	$(SILENT)mkdir -p ghdl-build
	$(foreach l,$(libraries),$(if $(foreach f,$($l-sources),$(if $(filter vhdl,$($f-language)),$f)),$(call ghdl-library-rules,$l)))
	$(SILENT)$(GHDL) -m \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
endef

define yosys-ghdl-ingress
endef

$(call workdir,$(target).vhd): $(sources) $(MAKEFILE_LIST)
	$(ghdl-analyze)
	$(SILENT)$(GHDL) --synth  -v \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity) > $@ || (rm $@ ; exit 1)

$(call workdir,$(target)-analyze.ys): $(sources) $(MAKEFILE_LIST)
	$(ghdl-analyze)
	$(SILENT)> $@
	$(SILENT)echo ghdl \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity) >> $@

$(call workdir,$(target).v): $(call workdir,$(target)-analyze.ys)
	$(SILENT)echo "script $<" > $@.ys
	$(SILENT)echo "write_verilog $@" >> $@.ys
	$(SILENT)$(YOSYS) -m $(YOSYS-GHDL) -s $@.ys

$(call workdir,$(target)-opt.v): $(call workdir,$(target)-analyze.ys)
	$(SILENT)echo "script $<" > $@.ys
	$(SILENT)echo "select $(top-entity)" > $@
	$(SILENT)echo "flatten" >> $@.ys
	$(SILENT)echo "opt" >> $@.ys
	$(SILENT)echo "write_verilog $@" >> $@.ys
	$(SILENT)$(YOSYS) -m $(YOSYS-GHDL) -s $@.ys

$(call workdir,$(target)-ice40.json): $(call workdir,$(target)-analyze.ys)
	$(SILENT)echo "script $<" > $@.ys
	$(SILENT)echo "synth_ice40 -top $(top-entity) -json $@" >> $@.ys
	$(SILENT)$(YOSYS) -m $(YOSYS-GHDL) -s $@.ys

$(call workdir,$(target)-ice40.pcf): $(filter %.pcf,$(sources)) $(MAKEFILE_LIST)
	cat $(filter %.pcf,$^) < /dev/null > $@

$(call workdir,$(target)-ice40.asc): $(call workdir,$(target)-ice40.json) $(call workdir,$(target)-ice40.pcf)
	nextpnr-ice40 --up5k \
		--package sg48 \
		--pcf $(filter %.pcf,$^) \
		--asc $@ \
		--json $< \
		--top '$(top-entity)'

$(call workdir,$(target)-ice40.bin): $(call workdir,$(target)-ice40.asc)
	icepack $< $@

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
