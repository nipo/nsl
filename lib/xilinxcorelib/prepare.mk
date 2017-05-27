ISE = $(HOME)/local/opt/Xilinx/14.7
ISE_VHDL = $(ISE)/ISE_DS/ISE/vhdl/src
XILINXCORELIB_VHDL = $(ISE_VHDL)/xilinxcorelib

ISE_XILINXCORELIB_SRC := $(shell cat $(XILINXCORELIB_VHDL)/vhdl_analyze_order | grep '\.vhd$$' | uniq)

update: Makefile

Makefile: $(ISE_XILINXCORELIB_SRC)
	@> $@
	@for src in $^ ; do \
		echo vhdl-sources += $${src} >> $@ ; \
	done

define component_declare

$(1): $$(XILINXCORELIB_VHDL)/$(1)
	@cp $$< $$@

endef

$(eval $(foreach i,$(ISE_XILINXCORELIB_SRC),$(call component_declare,$i)))

clean:
	rm -f Makefile *.vhd
