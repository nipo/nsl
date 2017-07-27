VHDL_VERSION=93
VHDL_VARIANT=c
GHDL=ghdl
target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

define ghdl_source_do
	$(GHDL) $2 --std=$(VHDL_VERSION)$(VHDL_VARIANT) --ieee=synopsys -v --work=$($1-library) $1
	$(SILENT)
endef

define ghdl_lib_do
$1-obj$(VHDL_VERSION).cf:
	$(SILENT)$(foreach s,$($1-lib-sources),$(call ghdl_source_do,$s,-i))

endef

$(eval $(foreach l,$(libraries),$(call ghdl_lib_do,$l)))

$(target).ghw: $(foreach l,$(libraries),$l-obj$(VHDL_VERSION).cf) FORCE
	$(SILENT)$(GHDL) -c -r --work=$(top-lib) $(top-entity) --wave=$@ $(GHDLRUNFLAGS)

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf
