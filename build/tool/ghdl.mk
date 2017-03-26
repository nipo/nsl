VHDL_VERSION=93
VHDL_VARIANT=c
GHDL=ghdl

simulate: $(top).vcd

$(top).vcd: $(top)
	./$(top) --vcd=$@ $(GHDLRUNFLAGS)

.PRECIOUS: $(top).vcd

elaborate: $(top)

$(top): $(foreach l,$(libraries),$l-obj$(VHDL_VERSION).cf)
	$(GHDL) -e $(GHDLFLAGS) $(top)

analyze: $(foreach l,$(libraries),$l-obj$(VHDL_VERSION).cf)

define ghdl_source_do
$$(GHDL) $1 --std=$$(VHDL_VERSION)$$(VHDL_VARIANT) --work=$2 $3
	
endef


define ghdl_library

$1-obj$$(VHDL_VERSION).cf: $($1-vhdl-sources)
	rm -f $$@
	$(foreach s,$($1-vhdl-sources),$(call ghdl_source_do,-i,$1,$s))
	$(foreach s,$($1-vhdl-sources),$(call ghdl_source_do,-a,$1,$s))

clean-files += $1-obj$$(VHDL_VERSION).cf

endef

clean-files += *.o $(top) $(top).vcd *.cf

$(eval $(foreach l,$(libraries),$(call ghdl_library,$l)))
