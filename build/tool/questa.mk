QUESTA = /opt/Altera/24.2/questa_fse
QUESTA_BIN = $(QUESTA)/bin/vsim
target ?= $(top)

SHELL=/bin/bash

define file-clear
	$(SILENT)mkdir -p $(dir $1)
	$(SILENT)> $1

endef

define file-append
	$(SILENT)echo '$2' >> $1

endef

define _questa-command-add-lib
	$(call file-append,$1,vlib -quiet $2)

endef

clean-dirs += $(build-dir)

_QUESTA_VHDL_VERSION_87 := 87
_QUESTA_VHDL_VERSION_93 := 93
_QUESTA_VHDL_VERSION_02 := 2002
_QUESTA_VHDL_VERSION_08 := 2008
_QUESTA_VHDL_VERSION_19 := 2019

define _questa-command-add-vhdl
	$(call file-append,$1,vcom -quiet -nologo -work $($2-library) -$(_QUESTA_VHDL_VERSION_$($($2-library)-vhdl-version)) -noautoorderrefresh $2)

endef

define _questa-command-add-verilog
	$(call file-append,$1,vlog -quiet -nologo -work $($2-library) $2)

endef

$(build-dir)/sources.do: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(foreach l,$(libraries),$(call _questa-command-add-lib,$@,$l))
	$(foreach s,$(sources),$(call _questa-command-add-$($s-language),$@,$s))

$(build-dir)/project.do: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,project new . $(top-entity) $(top-lib))
	$(foreach s,$(sources),$(call _questa-project-add-$($s-language),$@,$s))

$(build-dir)/simulate.do: $(build-dir)/sources.do $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,source $(build-dir)/sources.do)
	$(call file-append,$@,vsim $(foreach x,$(topcell-generics),-g$x) -quiet -work $(top-lib) $(top-entity) +dumpports+nocollapse)
#	$(call file-append,$@,vcd dumpports -file $(top-entity).vcd /*)
	$(call file-append,$@,onfinish default)
	$(call file-append,$@,run -all)
	$(call file-append,$@,puts "Error level [coverage attribute -name TESTSTATUS -concise]")
	$(call file-append,$@,quit -f -code [coverage attribute -name TESTSTATUS -concise])

define _questa-project-add-lib
	$(call file-append,$1,$2 = $2)

endef

define _questa-project-add-vhdl
	$(call file-append,$1,Project_File_'$$(grep -c Project_File_P_ $@)' = $2)
	$(call file-append,$1,Project_File_P_'$$(grep -c Project_File_P_ $@)' = vhdl_novitalcheck 0 file_type vhdl group_id 0 cover_nofec 0 vhdl_nodebug 0 vhdl_1164 1 vhdl_noload 0 vhdl_synth 0 vhdl_enable0In 0 folder {Top Level} last_compile 1733739911 vhdl_disableopt 0 vhdl_vital 0 cover_excludedefault 0 vhdl_warn1 1 vhdl_warn2 1 vhdl_explicit 1 vhdl_showsource 0 vhdl_warn3 1 cover_covercells 0 vhdl_0InOptions {} vhdl_warn4 1 voptflow 1 cover_optlevel 3 vhdl_options {} vhdl_warn5 1 toggle - ood 0 cover_noshort 0 compile_to $($2-library) compile_order '$$(grep -c Project_File_P_ $@)'  cover_nosub 0 dont_compile 0 vhdl_use93 $(_QUESTA_VHDL_VERSION_$($($2-library)-vhdl-version)))

endef

define _questa-project-add-verilog
	$(call file-append,$1,Project_File_'$$(grep -c Project_File_P_ $@)' = $2)
	$(call file-append,$1,Project_File_P_'$$(grep -c Project_File_P_ $@)' = file_type vhdl folder {Top Level} compile_to $($2-library) vhdl_use93 $(_QUESTA_VHDL_VERSION_$($($2-library)-vhdl-version))

endef

$(build-dir)/project_files.mpf.part: $(sources) $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(foreach s,$(sources),$(call _questa-project-add-$($(s)-language),$@,$s))

$(build-dir)/$(top-entity).mpf: $(build-dir)/project_files.mpf.part $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(SILENT)cat $(BUILD_ROOT)/support/questa_base.mpf >> $@
	$(call file-append,$@,Project_DefaultLib = $(top-lib))
	$(call file-append,$@,Project_Files_Count = '$$(grep -c Project_File_P_ $(build-dir)/project_files.mpf.part)')
	$(SILENT)cat $(build-dir)/project_files.mpf.part >> $@

simulate: $(build-dir)/simulate.do $(MAKEFILE_LIST)
	$(SILENT)cd $(build-dir) ; $(QUESTA_BIN) -batch -quiet -do $(build-dir)/simulate.do

$(build-dir)/gui.do: $(MAKEFILE_LIST)
	$(call file-clear,$@)
	$(call file-append,$@,vsim $(foreach x,$(topcell-generics),-g$x) -gui $(top-lib).$(top-entity))
	$(call file-append,$@,onfinish stop)
	$(call file-append,$@,run -all)

gui: $(build-dir)/$(top-entity).mpf $(build-dir)/gui.do $(MAKEFILE_LIST)
	$(SILENT)cd $(build-dir) ; $(QUESTA_BIN) -gui $< -do $(build-dir)/gui.do
