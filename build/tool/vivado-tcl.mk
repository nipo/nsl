
$(call exclude-libs,unisim xilinxcorelib)

include $(TOOL_ROOT)/vivado-create.inc.mk

all: sources.tcl

sources.tcl: $(sources) $(MAKEFILE_LIST)
	$(SILENT)$(call file-clear,$@)
	$(SILENT)$(call vivado-tcl-sources-append,$@,sources_1,constrs_1)
