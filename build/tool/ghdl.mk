VHDL_VERSION=93
VHDL_VARIANT=c
GHDL=ghdl

simulate: $(top).ghw

.PRECIOUS: $(top).ghw

.PHONY: FORCE

$(top).ghw: $(foreach l,$(libraries),$l-obj$(VHDL_VERSION).cf) FORCE
	@$(GHDL) -c -r $(top) --wave=$@ $(GHDLRUNFLAGS)

analyze: $(foreach l,$(libraries),$l-obj$(VHDL_VERSION).cf)

define ghdl_source_do
@$$(GHDL) $1 --std=$$(VHDL_VERSION)$$(VHDL_VARIANT) -v --work=$2 $3 > /dev/null
	
endef


define ghdl_library

$1-obj$$(VHDL_VERSION).cf: $($1-vhdl-sources)
	@rm -f $$@
	$(foreach s,$($1-vhdl-sources),$(call ghdl_source_do,-i,$1,$s))
	$(foreach s,$($1-vhdl-sources),$(call ghdl_source_do,-a,$1,$s))

clean-files += $1-obj$$(VHDL_VERSION).cf

endef

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf

$(eval $(foreach l,$(libraries),$(call ghdl_library,$l)))
