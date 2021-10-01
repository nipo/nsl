INTF_STYLE = $(if $V,,-intstyle silent)

MAP_PLACE_ROUTE_OPTS = -ol high -xe c

MAP_OPTS        = $(MAP_PLACE_ROUTE_OPTS) -mt on
PAR_OPTS        = $(MAP_PLACE_ROUTE_OPTS)
MAP_OPTS        += -global_opt speed -retiming on
MAP_OPTS        += -register_duplication on
MAP_OPTS        += -equivalent_register_removal off -lc area

# They should be the same, anyway
MAP_OPTS_GUIDED = $(MAP_OPTS)
PAR_OPTS_GUIDED = $(PAR_OPTS)

ISE = /opt/Xilinx/14.7/ISE_DS
ISE_PRE = source $(ISE)/settings64.sh > /dev/null ;
target ?= $(top)
user_id := $(shell python3 -c 'import random ; print(hex(random.randint(0, 1<<32)))')

export I

$(call exclude-libs,unisim)

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
	$(SILENT)CABLEDB=$(HOME)/projects/proby/support/xc3sprog/cablelist.txt \
	xc3sprog -v -p 2 -c proby -I$(NOPROB_ROOT)/fpga/bscan_spi.bit $(<):W:0:MCS

%.mcs: %.bit
	$(ISE_PRE) promgen -spi -w -p mcs -o $@ -u 0 $<

clean-files += $(target).mcs
clean-files += $(target)-2.mcs
clean-files += $(target)-2.cfi
clean-files += $(target)-2.prm

%.bit: $(build-dir)/%-par.ncd
	$(SILENT)$(ISE_PRE) bitgen $(INTF_STYLE) \
	    -g DriveDone:yes \
	    -g unusedpin:pullnone \
	    -g UserID:$(user_id) \
	    -g StartupClk:Cclk \
	    -w $< \
	    $@

clean-files += $(target).bit

%-compressed.bit: $(build-dir)/%-par.ncd
	$(SILENT)$(ISE_PRE) bitgen $(INTF_STYLE) \
	    -g DriveDone:yes \
	    -g unusedpin:pullnone \
	    -g compress \
	    -g UserID:$(user_id) \
	    -g StartupClk:Cclk \
	    -w $< \
	    $@

clean-files += $(target)-compressed.bit

$(build-dir)/%-2.bit: $(build-dir)/%-par.ncd
	$(SILENT)$(ISE_PRE) bitgen $(INTF_STYLE) \
	    -g spi_buswidth:2 \
	    -g unusedpin:pullnone \
	    -g ConfigRate:26 \
	    -g UserID:$(user_id) \
	    -g DriveDone:yes \
	    -g StartupClk:Cclk \
	    -w $< \
	    $@

clean-dirs += $(build-dir) _xmsgs xlnx_auto_0_xdb

%.mcs: %.bit
	$(SILENT)$(ISE_PRE) promgen $(INTF_STYLE) -w -p mcs -spi -c FF -o $@ -u 0 $<

$(build-dir)/$(target)-first-map.ncd $(build-dir)/$(target)-map.ncd:
	$(SILENT)$(ISE_PRE) map $(INTF_STYLE) -p $(target_part)$(target_package)$(target_speed) \
		$(if $(filter %-par.ncd,$^),$(MAP_OPTS_GUIDED),$(MAP_OPTS)) \
		$(foreach g,$(filter %-par.ncd,$^),-smartguide "$g") \
		-w "$(filter %.ngd,$^)" -o "$@"

$(build-dir)/$(target)-first-par.ncd $(build-dir)/$(target)-par.ncd:
	$(SILENT)$(ISE_PRE) par $(INTF_STYLE) \
		$(if $(filter %-par.ncd,$^),$(PAR_OPTS_GUIDED),$(PAR_OPTS)) \
		$(foreach g,$(filter %-par.ncd,$^),-smartguide "$g") \
		-w "$(filter %-map.ncd,$^)" "$@"
	$(SILENT)test 0 -eq `grep -c UNLOC $(@:.ncd=_pad.csv)` || (echo "There are unconstrained IOs"; exit 1)

$(build-dir)/$(target)-first-map.ncd: $(build-dir)/$(target).ngd
$(build-dir)/$(target)-first-par.ncd: $(build-dir)/$(target)-first-map.ncd
$(build-dir)/$(target)-map.ncd: $(build-dir)/$(target).ngd $(build-dir)/$(target)-first-par.ncd
$(build-dir)/$(target)-par.ncd: $(build-dir)/$(target)-map.ncd $(build-dir)/$(target)-first-par.ncd

define arg_add
\$(empty_variable)
    $1 $2
endef

define ccf_gen

$(build-dir)/$(notdir $(f:.ccf=.ucf)): $f $(build-dir)/$(target).ndf
	bash $(BUILD_ROOT)/support/ccf_ucf_gen $(build-dir)/$(target).ndf < $$< > $$@

endef

$(eval $(foreach f,$(filter %.ccf,$(all-constraint-sources)),$(call ccf_gen,$f)))

$(build-dir)/$(target).ndf: $(build-dir)/$(target).ngc
	$(SILENT)$(ISE_PRE) ngc2edif $(INTF_STYLE) -w $< $@

$(build-dir)/$(target).ngd: $(build-dir)/$(target).ngc $(filter %.ucf,$(all-constraint-sources)) $(foreach f,$(filter %.ccf,$(all-constraint-sources)),$(build-dir)/$(notdir $(f:.ccf=.ucf)))
	$(SILENT)echo "//" > $(@:.ngd=.bmm)
	$(SILENT)$(ISE_PRE) ngdbuild $(INTF_STYLE) -quiet -dd $(build-dir) \
	    $(foreach c,$(filter %.ngc,$(sources)),-sd $(dir $c)) \
	    $(foreach c,$(filter %.ngc,$^),$(call arg_add,$c)) \
	    $(foreach c,$(filter %.ucf,$^),$(call arg_add,-uc,$c)) \
	    -bm $(@:.ngd=.bmm) \
	    $@

%-map.pcf: %-map.ncd
	@

.PRECIOUS: %-map.pcf

define ise_source_vhdl_do
	$(SILENT)echo 'vhdl $($2-library) $2' >> $1

endef

define ise_source_verilog_do
	$(SILENT)echo 'verilog $($2-library) $2' >> $1

endef

define file_append
	$(SILENT)cat $1 >> $2

endef

clean-files += $(build-dir)/$(target).prj
clean-files += $(build-dir)/$(target).ngc
clean-files += $(build-dir)/$(target).twr

$(build-dir)/$(target).prj: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(dir $@)
	$(SILENT)> $@
	$(foreach s,$(sources),$(call ise_source_$($s-language)_do,$@,$s))

$(build-dir)/$(target).ngc: $(build-dir)/$(target).prj $(OPS)
	$(SILENT)mkdir -p $(build-dir)/xst
	$(SILENT)echo 'set -tmpdir "$(build-dir)/xst"' > $@.xst
	$(SILENT)echo 'set -xsthdpdir "$(build-dir)"' >> $@.xst
	$(SILENT)echo "run" >> $@.xst
	$(SILENT)echo "-p $(target_part)$(target_package)$(target_speed)" >> $@.xst
	$(SILENT)echo "-top $(top-entity)" >> $@.xst
	$(SILENT)echo "-ifn $<" >> $@.xst
	$(SILENT)echo "-ofn $@" >> $@.xst
	$(SILENT)echo "-max_fanout 15" >> $@.xst
	$(SILENT)echo "-keep_hierarchy soft" >> $@.xst
	$(SILENT)echo "-read_cores yes" >> $@.xst
#	$(SILENT)echo "-lc No" >> $@.xst
	$(SILENT)echo "-equivalent_register_removal no" >> $@.xst
#	$(SILENT)echo "-register_balancing yes" >> $@.xst
	$(SILENT)$(foreach f,$(OPS),$(call file_append,$f,$@.xst))
	$(SILENT)$(ISE_PRE) xst $(INTF_STYLE) -ifn $@.xst -ofn $@.log

$(build-dir)/%.twr: $(build-dir)/%-par.ncd $(build-dir)/%-map.pcf
	$(SILENT)$(ISE_PRE) trce -v 10 $(filter %.ncd,$^) $(filter %.pcf,$^) -o $@

$(build-dir)/%.vhd: $(build-dir)/%.ncd
	$(SILENT)$(ISE_PRE) netgen -sim -ofmt vhdl -w $< $@
