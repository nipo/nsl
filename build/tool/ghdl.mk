target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

_GHDL_STD_1993=93c
_GHDL_STD_2008=08
_GHDL_CF_SUFFIX_1993=93
_GHDL_CF_SUFFIX_2008=08
GHDL_VPI_LIB_DIR:=$(shell $(GHDL) --vpi-library-dir)


lib_cf = $(call workdir,$1)/$1-obj$(_GHDL_CF_SUFFIX_$($1-vhdl-version)).cf

clean-dirs += $(build-dir)

vhpidirect-plugin := $(sorted $(vhpidirect-plugin))
vpi-plugin := $(sorted $(vpi-plugin))

ifeq ($(GHDL_LLVM),)
# GHDL Without LLVM

workdir = $(if $(filter $(top-lib),$1),.,$(build-dir))

define ghdl-compile-rules
	$(SILENT)echo "[GHDL] Making design unit $(top-lib).$(top-entity)"
	$(SILENT)$(GHDL) -m \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
	$(SILENT)echo "[GHDL] Elaborating"
	$(SILENT)$(GHDL) -e \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
	rm -f $@
	echo '#!/bin/sh' > $@
	echo 'export LD_LIBRARY_PATH=$$LD_LIBRARY_PATH:$(build-dir)' >> $@
	echo 'export DYLD_LIBRARY_PATH=$$DYLD_LIBRARY_PATH:$(build-dir)' >> $@
	echo '$(GHDL) -r \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),$($l-ghdl-flags))) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity) \
		$(foreach x,$(topcell-generics),-g$x) \
		$(foreach l,$(vpi-plugin),--vpi=$(build-dir)/$l-vpi.so) \
		--ieee-asserts=disable --unbuffered $$*' >> $@
	chmod +x $@
endef

define ghdl-run-rules
	./$< $1
endef

else
# GHDL + LLVM mode

workdir = $(build-dir)/$1

define ghdl-compile-rules
	$(SILENT)echo "[GHDL/LLVM] Compiling"
	$(SILENT)$(GHDL) -c -v -O2 \
		--workdir=$(call workdir,$(top-lib)) \
		--std=$(_GHDL_STD_$($(top-lib)-vhdl-version)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(foreach l,$(libraries),$($l-ghdl-flags)) \
		$(foreach l,$(vhpidirect-plugin),-Wl,$(build-dir)/$l-vhpidirect.so) \
		--work=$(top-lib) -e $(top-entity)

endef

define ghdl-run-rules
	./$< $(foreach l,$(vpi-plugin),--vpi=$(build-dir)/$l-vpi.so) $1
endef

endif

define ghdl-library-analyze-rules
	$(SILENT)echo "[GHDL] Analyzing $1"
	$(SILENT)$(GHDL) -a \
		--workdir=$(call workdir,$1) \
		$(sort $(foreach l,$($1-libdeps-unsorted),-P$(call workdir,$l))) \
		--std=$(_GHDL_STD_$($1-vhdl-version)) \
		$($l-ghdl-flags) \
		--work=$1 \
		$(foreach f,$($1-sources),$(if $(filter vhdl,$($f-language)),$f))

endef

define ghdl-library-rules
	$(SILENT)echo "[GHDL] Importing $1: $(subst $1.,,$($1-packages))"
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

define vhpidirect-plugin-compile-rule

$(build-dir)/$1-vhpidirect.so: $($1-plugin-sources)
	$(SILENT)mkdir -p $(build-dir)
	gcc -shared -fPIC -o $$@ $$<

endef

$(eval $(foreach p,$(vhpidirect-plugin),$(call vhpidirect-plugin-compile-rule,$p)))


define vpi-plugin-compile-rule

$(build-dir)/$1-vpi.so: $($1-plugin-sources)
	$(SILENT)mkdir -p $(build-dir)
	$(GHDL) --vpi-compile gcc -c -o $(build-dir)/$1.o  $$< -W -Wall -O2  -DVPI_DO_NOT_FREE_CALLBACK_HANDLES
	$(GHDL) --vpi-link gcc -shared -fPIC -o $$@ $(build-dir)/$1.o -lm -L$(GHDL_VPI_LIB_DIR)

endef

$(eval $(foreach p,$(vpi-plugin),$(call vpi-plugin-compile-rule,$p)))

$(target): $(sources) $(MAKEFILE_LIST) $(foreach l,$(vhpidirect-plugin),$(build-dir)/$l-vhpidirect.so) $(foreach l,$(vpi-plugin),$(build-dir)/$l-vpi.so)
	$(SILENT)echo "[GHDL] Backend: $(ghdl-backend)"
	$(SILENT)mkdir -p $(build-dir)
	$(foreach l,$(libraries),$(if $(foreach f,$($l-sources),$(if $(filter vhdl,$($f-language)),$f)),$(call ghdl-library-rules,$l)))
	$(call ghdl-compile-rules)

run: $(target)
	$(call ghdl-run-rules,)

headless_run: $(target).log

$(target).log: $(target)
	$(call ghdl-run-rules,) > $@.tmp
	cp $@.tmp $@

$(target).ghw: $(target)
	$(call ghdl-run-rules,--wave=$@)

$(target).fst: $(target)
	$(call ghdl-run-rules,--fst=$@)

$(target).vcd: $(target)
	$(call ghdl-run-rules,--vcd=$@)

clean-files += *.o $(target) $(target).ghw $(target).vcd $(target).vcd *.cf *.lst $(target) $(target).log
