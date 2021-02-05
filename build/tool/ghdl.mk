GHDL=ghdl
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

ifeq ($(GHDL_LLVM),)
# GHDL Without LLVM

workdir = $(if $(filter $(top-lib),$1),.,ghdl-build)

define ghdl-library-analyze-rules
	$(SILENT)$(GHDL) -a \
		--workdir=$(call workdir,$1) \
		$(sort $(foreach l,$($1-libdeps-unsorted),-P$(call workdir,$l))) \
		--std=$(_GHDL_STD_$($1-vhdl-version)) \
		$($l-ghdl-flags) \
		--work=$1 \
		$(foreach f,$($1-sources),$(if $(filter vhdl,$($f-language)),$f))

endef

define ghdl-compile-rules
	$(SILENT)$(GHDL) -m \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
	$(SILENT)$(GHDL) -e \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity)
endef

define ghdl-run-rules
	$(SILENT)$(GHDL) -r \
		--workdir=$(call workdir,$(top-lib)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(sort $(foreach l,$(libraries),-P$(call workdir,$(top-lib)))) \
		--work=$(top-lib) $(top-entity) \
		 --wave=$@ --ieee-asserts=disable
endef

else
# GHDL + LLVM mode

workdir = ghdl-build/$1
ghdl-library-analyze-rules :=
define ghdl-compile-rules
	$(SILENT)$(GHDL) -m -v \
		--workdir=$(call workdir,$(top-lib)) \
		--std=$(_GHDL_STD_$($(top-lib)-vhdl-version)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(foreach l,$(libraries),$($l-ghdl-flags)) \
		--work=$(top-lib) $(top-entity)
	$(SILENT)$(GHDL) -c -v \
		--workdir=$(call workdir,$(top-lib)) \
		--std=$(_GHDL_STD_$($(top-lib)-vhdl-version)) \
		$(foreach l,$(libraries),-P$(call workdir,$l)) \
		$(foreach l,$(libraries),$($l-ghdl-flags)) \
		--work=$(top-lib) -e $(top-entity)

endef

define ghdl-run-rules
	./$< --wave=$@
endef

endif

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

$(target): $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p ghdl-build
	$(foreach l,$(libraries),$(if $(foreach f,$($l-sources),$(if $(filter vhdl,$($f-language)),$f)),$(call ghdl-library-rules,$l)))
	$(call ghdl-compile-rules)

$(target).ghw: $(target)
	$(call ghdl-run-rules)

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
