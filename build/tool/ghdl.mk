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
		$(foreach l,$(all-vpi-plugins),--vpi=$l) \
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
		$(foreach l,$(all-vhpidirect-plugins),-Wl,$l) \
		--work=$(top-lib) -e $(top-entity)

endef

define ghdl-run-rules
	./$< $(foreach l,$(all-vpi-plugins),--vpi=$l) $1
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

$($1-library)/$($1-package)-vhpidirect.so: $(foreach s,$(all-vhpidirect-sources),$(if $(filter $1,$($s-package)),$s)) $(BUILD_ROOT)/support/vhpidirect/vhpidirect_user.h
	$(SILENT)mkdir -p $($1-library)
	gcc -shared -fPIC -o $$@ $$(filter %.c,$$^) -I$(BUILD_ROOT)/support/vhpidirect

all-vhpidirect-plugins += $($1-library)/$($1-package)-vhpidirect.so

endef

all-vhpidirect-plugins :=
$(eval $(foreach p,$(sort $(foreach s,$(all-vhpidirect-sources),$($s-package))),$(call vhpidirect-plugin-compile-rule,$p)))

define vpi-plugin-compile-rule

$($1-library)/$($1-package)-vpi.so: $(foreach s,$(all-vpi-sources),$(if $(filter $1,$($s-package)),$s))
	$(SILENT)mkdir -p $($1-library)
	$(GHDL) --vpi-compile gcc -c -o $($1-library)/$1.o  $$^ -W -Wall -O2  -DVPI_DO_NOT_FREE_CALLBACK_HANDLES
	$(GHDL) --vpi-link gcc -shared -fPIC -o $$@ $($1-library)/$1.o -lm -L$(GHDL_VPI_LIB_DIR)

all-vpi-plugins += $($1-library)/$($1-package)-vpi.so

endef

all-vpi-plugins :=
$(eval $(foreach p,$(sort $(foreach s,$(all-vpi-sources),$($s-package))),$(call vpi-plugin-compile-rule,$p)))

$(target): $(sources) $(MAKEFILE_LIST) $(all-vhpidirect-plugins) $(all-vpi-plugins)
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
