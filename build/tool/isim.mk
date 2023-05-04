ISE = /opt/Xilinx/14.7/ISE_DS
#INTF_STYLE = -intstyle silent
ISE_PRE = source $(ISE)/settings64.sh > /dev/null ;
PAR_OPTS = -ol high
target ?= $(top)
target-usage = simulation

simulation-time ?= 10 ms

SHELL=/bin/bash

clean-files += par_usage_statistics.html
clean-files += usage_statistics_webtalk.html
clean-files += xilinx_device_details.xml
clean-files += webtalk.log
clean-files += $(target).bgn
clean-files += $(target).drc
clean-files += $(target).srp
clean-files += $(target)_bitgen.xwbt
clean-files += $(top-entity)_map.xrpt
clean-files += $(top-entity)_par.xrpt
clean-files += $(top-entity).lso
clean-files += isim.log
clean-files += fuse.log
clean-files += fuseRelaunch.cmd
clean-files += fuse.xmsgs
clean-files += isim.wdb
clean-files += $(target).vcd
clean-files += $(target).vcd.tmp
clean-dirs += isim

$(call exclude-libs,unisim simprim)

sim: $(target).vcd

clean-dirs += $(build-dir) _xmsgs xlnx_auto_0_xdb

$(build-dir)/$(target).exe: $(build-dir)/$(target).prj $(MAKEFILE_LIST)
	$(SILENT)$(ISE_PRE) \
	fuse $(INTF_STYLE) -incremental -v 2 -lib secureip -o $@ -prj $< $(top-lib).$(top-entity)

$(target).vcd: $(build-dir)/$(target).exe $(MAKEFILE_LIST)
	$(SILENT)> $@.tmp
	$(SILENT)echo 'onerror {resume}' >> $@.tmp
	$(SILENT)echo 'vcd dumpfile "$@"' >> $@.tmp
	$(SILENT)echo 'vcd dumpvars -m / -l 0' >> $@.tmp
	$(SILENT)echo 'wave add /' >> $@.tmp
	$(SILENT)echo 'run $(simulation-time)' >> $@.tmp
	$(SILENT)echo 'quit -f' >> $@.tmp
	$(SILENT)$(ISE_PRE) $< -tclbatch $@.tmp

gui: $(build-dir)/$(target).exe $(MAKEFILE_LIST)
	$(SILENT)$(ISE_PRE) $< -gui

define ise_source_do_vhdl
	echo "$($1-language) $($1-library) $1" >> $@.tmp
	$(SILENT)
endef

define ise_source_do_verilog
	echo "$($1-language) $($1-library) $1" >> $@.tmp
	$(SILENT)
endef

$(build-dir)/$(target).prj: $(sources) $(MAKEFILE_LIST)
	$(SILENT)mkdir -p $(build-dir)/xst
	$(SILENT)> $@.tmp
	$(SILENT)$(foreach s,$(sources),$(if $(filter constraint,$($s-language)),,$(call ise_source_do_$($(s)-language),$s)))
	$(SILENT)mv -f $@.tmp $@

