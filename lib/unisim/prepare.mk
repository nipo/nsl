ISE = $(HOME)/local/opt/Xilinx/14.7
ISE_VHDL = $(ISE)/ISE_DS/ISE/vhdl/src
UNISIM_VHDL = $(ISE_VHDL)/unisim

ISE_UNISIM_SRC := $(shell cat $(UNISIM_VHDL)/primitive/vhdl_analyze_order | uniq)

update: Makefile

Makefile: $(ISE_UNISIM_SRC) unisim_VPKG.vhd unisim_VCOMP.vhd
	@> $@
	@for src in $^ ; do \
		echo vhdl-sources += $${src} >> $@ ; \
	done

unisim_VPKG.vhd: $(UNISIM_VHDL)/unisim_VPKG.vhd
	@cp $< $@

unisim_VCOMP.vhd: $(UNISIM_VHDL)/unisim_VCOMP.vhd
	@cp $< $@

define component_declare

$(1): $$(UNISIM_VHDL)/primitive/$(1)
	@cp $$< $$@

endef

$(eval $(foreach i,$(ISE_UNISIM_SRC),$(call component_declare,$i)))

clean:
	rm -f Makefile *.vhd
