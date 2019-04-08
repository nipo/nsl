VHDL_VERSION=93
VHDL_VARIANT=c
GHDL=ghdl
target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

GHDL_OPTS = --std=$(VHDL_VERSION)$(VHDL_VARIANT) --ieee=synopsys
lib_cf = $(if $(filter $(top-lib),$1),,ghdl-build/$1/)$1-obj$(VHDL_VERSION).cf
#lib_cf = ghdl-build/$1/$1-obj$(VHDL_VERSION).cf

define ghdl_source_do
	$(GHDL) \
		$2 \
		 --workdir=$$(dir $$@) \
		$(foreach l,$($($1-library)-lib-deps),-Pghdl-build/$l) \
		$(GHDL_OPTS) \
		-v \
		--work=$($1-library) \
		$1
	$(SILENT)
endef

define ghdl_source_do2
	-$(GHDL) \
		$2 \
		 --workdir=$$(dir $$@) \
		$(foreach l,$($($1-library)-lib-deps),-Pghdl-build/$l) \
		$(GHDL_OPTS) \
		-v \
		--work=$($1-library) \
		$(subst .vhd,,$(notdir $1))
	$(SILENT)
endef

define ghdl_lib_do
$(call lib_cf,$1): $(foreach l,$($1-lib-deps),$(call lib_cf,$($l-library))) $($1-lib-sources)
	$(SILENT)echo Updating $$@, depends on $$^
	$(SILENT)mkdir -p $$(dir $$@)
	$(SILENT)$(foreach s,$($1-lib-sources),$(call ghdl_source_do,$s,-i))
	$(SILENT)$(foreach s,$($1-lib-sources),$(call ghdl_source_do,$s,-a))

clean-dirs += $(filter-out ./,$(dir $(call lib_cf,$1)))

$(target): $(call lib_cf,$1)

endef

clean-dirs += ghdl-build

#$(info $(libraries))
$(eval $(foreach l,$(libraries),$(call ghdl_lib_do,$l)))

$(target): FORCE
	$(SILENT)$(GHDL) -e -v \
		$(GHDL_OPTS) \
		$(foreach l,$(filter %.cf,$^),-P$(dir $l)) \
		$(top-entity)

$(target).ghw: $(target)
	$(SILENT)$(GHDL) -r -v \
		$(GHDL_OPTS) \
		$(foreach l,$(libraries),-P$(dir $(call lib_cf,$l))) \
		$(top-entity) --wave=$@

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
