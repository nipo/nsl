GHDL=ghdl
target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

_GHDL_STD_93=93c
_GHDL_STD_08=08
_GHDL_CF_SUFFIX_93=93
_GHDL_CF_SUFFIX_08=08
#workdir = $(if $(filter $(top-lib),$1),.,ghdl-build)
workdir = ghdl-build
lib_cf = $(call workdir,$1)/$1-obj$(_GHDL_CF_SUFFIX_$($1-vhdl-version)).cf

clean-dirs += ghdl-build

define ghdl-library-rules
	$(SILENT)$(GHDL) -i \
		--workdir=$(call workdir,$1) \
		$(sort $(foreach l,$($$1-libdeps-unsorted),-P$(call workdir,$l))) \
		--std=$(_GHDL_STD_$($1-vhdl-version)) \
		--work=$1 \
		$($1-sources)

endef

$(target):
	$(SILENT)mkdir -p ghdl-build
	$(foreach l,$(libraries),$(call ghdl-library-rules,$l))
	$(SILENT)$(GHDL) -m -v \
		--workdir=ghdl-build \
		--std=$(_GHDL_STD_$($(top-lib)-vhdl-version)) \
		-Pghdl-build \
		--work=$(top-lib) $(top-entity)
	$(SILENT)$(GHDL) -c -v \
		--workdir=ghdl-build \
		--std=$(_GHDL_STD_$($(top-lib)-vhdl-version)) \
		-Pghdl-build \
		--work=$(top-lib) -e $(top-entity)

$(target).ghw: $(target)
	./$< --wave=$@

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
