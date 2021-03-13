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

$(target).vhd: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p ghdl-build
	$(foreach l,$(libraries),$(if $(foreach f,$($l-sources),$(if $(filter vhdl,$($f-language)),$f)),$(call ghdl-library-rules,$l)))
	$(SILENT)$(GHDL) -m \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
	$(SILENT)echo ghdl \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity) > $(call workdir,$(target)-synth.ys)
	$(SILENT)echo "synth_ice40 -top $(top-entity) -retime -relut -blif $(call workdir,$(target).blif)" >> $(call workdir,$(target)-synth.ys)
	$(SILENT)$(YOSYS) -m $(YOSYS-GHDL) -s $(call workdir,$(target)-synth.ys)

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
