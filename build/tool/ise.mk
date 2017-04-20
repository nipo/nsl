ISE = /opt/Xilinx/14.7/ISE_DS
INTF_STYLE =
PAR_OPTS = -ol high

TMP = 

ISE_ENV = $(ISE)/settings64.sh

SHELL=/bin/bash

flash: $(top).bit
	openocd -f interface/jlink.cfg -f cpld/xilinx-xc6s.cfg -c "adapter_khz 1000; init; xc6s_program xc6s.tap; pld load 0 $<; exit"

spi-flash: $(top)-2.mcs
	CABLEDB=$(HOME)/projects/proby/support/xc3sprog/cablelist.txt \
	xc3sprog -v -p 2 -c proby -I$(NOPROB_ROOT)/fpga/bscan_spi.bit $(<):W:0:MCS

$(top).mcs: $(top).bit
	source $(ISE_ENV) ; \
	promgen -spi -w -p mcs -o $@ -u 0 $<

$(top)-2.mcs: ise-build/$(top)-2.bit
	source $(ISE_ENV) ; \
	promgen -spi -w -p mcs -o $@ -u 0 $<

$(top).bit: ise-build/$(top)_par.ncd
	source $(ISE_ENV) ; \
	bitgen $(INTF_STYLE) \
            -g DriveDone:yes \
            -g StartupClk:Cclk \
            -w $< \
	    $@

ise-build/$(top)-2.bit: ise-build/$(top)_par.ncd
	source $(ISE_ENV) ; \
	bitgen $(INTF_STYLE) \
            -g spi_buswidth:2 \
            -g ConfigRate:26 \
            -g DriveDone:yes \
            -g StartupClk:Cclk \
            -w $< \
	    $@

%.mcs: %.bit
	source $(ISE_ENV) ; \
	promgen $(INTF_STYLE) -w -p mcs -spi -c FF -o $@ -u 0 $<

ise-build/$(top)_par.ncd: ise-build/$(top).ncd
	source $(ISE_ENV) ; \
	par $(INTF_STYLE) $(PAR_OPTS) -w $< $@

ise-build/$(top).ncd: ise-build/$(top).ngd
	if [ -r ise-build/$(top)_par.ncd ]; then \
		cp ise-build/$(top)_par.ncd ise-build/smartguide.ncd; \
		SMARTGUIDE="-smartguide ise-build/smartguide.ncd"; \
	else \
		SMARTGUIDE=""; \
	fi; \
	source $(ISE_ENV) ; \
	map $(INTF_STYLE) $(MAP_OPTS) $${SMARTGUIDE} -w $<

ise-build/$(top).ngd: ise-build/$(top).ngc
	echo "//" > ise-build/$(top).bmm
	source $(ISE_ENV) ; \
	ngdbuild -dd ise-build \
	    $(INTF_STYLE) ise-build/$(top).ngc \
	    -uc $(BUILD_ROOT)/$(constraints) \
	    -bm ise-build/$(top).bmm \
	    $@

ise-build/$(top).ngc: $(foreach l,$(libraries),$($l-vhdl-sources)) ise-build/$(top).xst ise-build/$(top).prj
	source $(ISE_ENV) ; \
	xst $(INTF_STYLE) -ifn ise-build/$(top).xst

define ise_source_do
	echo "vhdl $1 $2" >> $@.tmp
	
endef


define ise_library_do
	$(foreach s,$($1-vhdl-sources),$(call ise_source_do,$1,$s))
	
endef

ise-build/$(top).prj: $(foreach l,$(libraries),$($l-vhdl-sources))
	> $@.tmp
	$(foreach l,$(libraries),$(call ise_library_do,$l))
	sort -u $@.tmp > $@
	rm -f $@.tmp

ise-build/$(top).xst: $(OPTS)
	mkdir -p ise-build/xst
	echo 'set -tmpdir "ise-build/xst"' > $@
	echo 'set -xsthdpdir "ise-build"' >> $@
	echo "run" >> $@
	echo "-p $(target_part)" >> $@
	echo "-top $(top)" >> $@
	echo "-ifn ise-build/$(top).prj" >> $@
	echo "-ofn ise-build/$(top).ngc" >> $@
	for o in $(OPTS) ; do \
	    cat $$o >> $@ ; \
	done

ise-build/$(top).post_map.twr: ise-build/$(top).ncd ise-build/$(top).pcf
	source $(ISE_ENV) ; \
	trce -e 10 $< ise-build/$(top).pcf -o $@

ise-build/$(top).twr: ise-build/$(top)_par.ncd
	source $(ISE_ENV) ; \
	trce $< ise-build/$(top).pcf -o $@

ise-build/$(top)_err.twr: ise-build/$(top)_par.ncd
	source $(ISE_ENV) ; \
	trce -e 10 $< ise-build/$(top).pcf -o $@
