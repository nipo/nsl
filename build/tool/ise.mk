ISE = /opt/Xilinx/14.7/ISE_DS
INTF_STYLE = -intstyle silent
PAR_OPTS = -ol high
ISE_PREPARE = source $(ISE)/settings64.sh > /dev/null
target ?= $(top)

SHELL=/bin/bash

clean-files += par_usage_statistics.html
clean-files += usage_statistics_webtalk.html
clean-files += xilinx_device_details.xml
clean-files += webtalk.log
clean-files += $(target).bgn
clean-files += $(target).drc
clean-files += $(target).srp
clean-files += $(target)_bitgen.xwbt
clean-files += $(top)_map.xrpt
clean-files += $(top)_par.xrpt
clean-files += $(top).lso

flash: $(target).bit
	openocd -f interface/jlink.cfg -f cpld/xilinx-xc6s.cfg -c "adapter_khz 1000; init; xc6s_program xc6s.tap; pld load 0 $<; exit"

spi-flash: $(target)-2.mcs
	CABLEDB=$(HOME)/projects/proby/support/xc3sprog/cablelist.txt \
	xc3sprog -v -p 2 -c proby -I$(NOPROB_ROOT)/fpga/bscan_spi.bit $(<):W:0:MCS

$(target).mcs: $(target).bit
	$(ISE_PREPARE) ; \
	promgen -spi -w -p mcs -o $@ -u 0 $<

clean-files += $(target).mcs

$(target)-2.mcs: ise-build/$(target)-2.bit
	$(ISE_PREPARE) ; \
	promgen -spi -w -p mcs -o $@ -u 0 $<

clean-files += $(target)-2.mcs
clean-files += $(target)-2.cfi
clean-files += $(target)-2.prm

$(target).bit: ise-build/$(target)_par.ncd
	$(ISE_PREPARE) ; \
	bitgen $(INTF_STYLE) \
            -g DriveDone:yes \
            -g StartupClk:Cclk \
            -w $< \
	    $@

clean-files += $(target).bit

$(target)-compressed.bit: ise-build/$(target)_par.ncd
	$(ISE_PREPARE) ; \
	bitgen $(INTF_STYLE) \
            -g DriveDone:yes \
            -g compress \
            -g StartupClk:Cclk \
            -w $< \
	    $@

clean-files += $(target)-compressed.bit

ise-build/$(target)-2.bit: ise-build/$(target)_par.ncd
	$(ISE_PREPARE) ; \
	bitgen $(INTF_STYLE) \
            -g spi_buswidth:2 \
            -g ConfigRate:26 \
            -g DriveDone:yes \
            -g StartupClk:Cclk \
            -w $< \
	    $@

clean-dirs += ise-build _xmsgs xlnx_auto_0_xdb

%.mcs: %.bit
	$(ISE_PREPARE) ; \
	promgen $(INTF_STYLE) -w -p mcs -spi -c FF -o $@ -u 0 $<

ise-build/$(target)_par.ncd: ise-build/$(target).ncd
	$(ISE_PREPARE) ; \
	par $(INTF_STYLE) $(PAR_OPTS) -w $< $@

ise-build/$(target).ncd: ise-build/$(target).ngd
	if [ -r ise-build/$(target)_par.ncd ]; then \
		cp ise-build/$(target)_par.ncd ise-build/smartguide.ncd; \
		SMARTGUIDE="-smartguide ise-build/smartguide.ncd"; \
	else \
		SMARTGUIDE=""; \
	fi; \
	$(ISE_PREPARE) ; \
	map $(INTF_STYLE) $(MAP_OPTS) $${SMARTGUIDE} -w $<

ise-build/$(target).ngd: ise-build/$(target).ngc $(constraints)
	echo "//" > ise-build/$(target).bmm
	$(ISE_PREPARE) ; \
	ngdbuild -dd ise-build \
	    $(INTF_STYLE) ise-build/$(target).ngc \
		$(foreach c,$(constraints),-uc $c) \
	    -bm ise-build/$(target).bmm \
	    $@

ise-build/$(target).ngc: $(foreach l,$(libraries),$($l-vhdl-sources)) ise-build/$(target).xst ise-build/$(target).prj
	$(ISE_PREPARE) ; \
	xst $(INTF_STYLE) -ifn ise-build/$(target).xst

define ise_source_do
	echo "vhdl $1 $2" >> $@.tmp
	
endef


define ise_library_do
	$(foreach s,$($1-vhdl-sources),$(call ise_source_do,$1,$s))
	
endef

ise-build/$(target).prj: $(foreach l,$(libraries),$($l-vhdl-sources))
	mkdir -p ise-build/xst
	> $@.tmp
	$(foreach l,$(libraries),$(call ise_library_do,$l))
	sort -u $@.tmp > $@
	rm -f $@.tmp

ise-build/$(target).xst: ise-build/$(target).prj $(OPTS)
	echo 'set -tmpdir "ise-build/xst"' > $@
	echo 'set -xsthdpdir "ise-build"' >> $@
	echo "run" >> $@
	echo "-p $(target_part)" >> $@
	echo "-top $(top)" >> $@
	echo "-ifn ise-build/$(target).prj" >> $@
	echo "-ofn ise-build/$(target).ngc" >> $@
	for o in $(OPTS) ; do \
	    cat $$o >> $@ ; \
	done

ise-build/$(target).post_map.twr: ise-build/$(target).ncd ise-build/$(target).pcf
	$(ISE_PREPARE) ; \
	trce -e 10 $< ise-build/$(target).pcf -o $@

ise-build/$(target).twr: ise-build/$(target)_par.ncd
	$(ISE_PREPARE) ; \
	trce $< ise-build/$(target).pcf -o $@

ise-build/$(target)_err.twr: ise-build/$(target)_par.ncd
	$(ISE_PREPARE) ; \
	trce -e 10 $< ise-build/$(target).pcf -o $@
