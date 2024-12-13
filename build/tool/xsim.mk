VIVADO = /opt/Xilinx/Vivado/2019.2
VIVADO_SETTINGS = /opt/Xilinx/Vivado/2019.2/settings64.sh
VIVADO_PREPARE = source $(VIVADO_SETTINGS) > /dev/null
target ?= $(top)

simulation-time ?= 10 ms

SHELL=/bin/bash

clean-files += xelab.pb
clean-files += xsim.jou
clean-files += xvhdl.log
clean-files += xvlog.log
clean-files += compile.log
clean-files += elaborate.log
clean-files += simulate.log
clean-files += xelab.log
clean-files += xsim.log
clean-files += run.log
clean-files += xvhdl.pb
clean-files += xvlog.pb
clean-files += $(target).wdb

$(call exclude-libs,unisim simprim)

sim: simulate

clean-dirs += $(build-dir) xsim.dir

define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define xsim-vhdl-lib-add-vhdl
	$(call file-append,$1, "$2" \)

endef

define xsim-vhdl-lib-prj
	$(call file-append,$1,vhdl $2 \)
	$(foreach f,$($2-sources),$(call xsim-vhdl-lib-add-$($f-language),$1,$f))
	$(call file-append,$1,)

endef

define xsim-verilog-lib-add-verilog
	$(call file-append,$1, "$2" \)

endef

# TODO: add include paths with
#  verilog <lib_name> --include "path" --include "path" ...
# TODO: also call this for sv libraries
#  sv <lib_name> --include "path" --include "path" ...
define xsim-verilog-lib-prj
	$(call file-append,$1,verilog $2 \)
	$(foreach f,$($2-sources),$(call xsim-verilog-lib-add-$($f-language),$1,$f))
	$(call file-append,$1,)

endef

define xsim-ini-lib
	$(call file-append,$1,$2=xsim.dir/$2)

endef

$(build-dir)/vhdl.prj: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(foreach l,$(libraries),$(if $(filter vhdl,$(sort $(foreach f,$($l-sources),$($f-language)))),$(call xsim-vhdl-lib-prj,$@,$l)))
	$(call file-append,$@,nosort)

$(build-dir)/vlog.prj: $(sources) $(MAKEFILE_LIST) $(build-dir)/glbl.v
	$(call file-clear,$@)
	$(foreach l,$(libraries),$(if $(filter verilog,$(sort $(foreach f,$($l-sources),$($f-language)))),$(call xsim-verilog-lib-prj,$@,$l)))
	$(call file-append,$@,verilog xil_defaultlib "glbl.v")
	$(call file-append,$@,nosort)

$(build-dir)/xsim.ini: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(foreach l,$(libraries),$(call xsim-ini-lib,$@,$l))

$(build-dir)/glbl.v: $(BUILD_ROOT)/support/xsim_glbl.v
	$(SILENT)cp $< $@

$(build-dir)/elaborate.log: $(VIVADO_SETTINGS) $(build-dir)/vhdl.prj $(build-dir)/vlog.prj $(build-dir)/xsim.ini
	$(SILENT)$(VIVADO_PREPARE) ; cd $(build-dir) ; xvlog --relax -prj vlog.prj
	$(SILENT)$(VIVADO_PREPARE) ; cd $(build-dir) ; xvhdl --relax -prj vhdl.prj
	$(SILENT)$(VIVADO_PREPARE) ; cd $(build-dir) ; xelab --relax --debug typical --mt auto $(foreach l,$(libraries),-L $l) $(top-lib).$(top-entity) -log elaborate.log

simulate: $(VIVADO_SETTINGS) $(build-dir)/elaborate.log
	$(SILENT)$(VIVADO_PREPARE) ; cd $(build-dir) ; xsim $(top-entity) -key "{Behavioral:sim_1:Functional:$(top-entity)}"  -onerror quit -runall

gui: $(VIVADO_SETTINGS)$(build-dir)/elaborate.log
	$(SILENT)$(VIVADO_PREPARE) ; cd $(build-dir) ; xsim $(top-entity) -key "{Behavioral:sim_1:Functional:$(top-entity)}" -g
