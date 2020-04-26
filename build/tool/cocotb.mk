
simulate: cocotb-build/Makefile
	$(MAKE) -C $(dir $<) sim

define append
	$(SILENT)echo '$2' >> $1

endef

define source_append_vhdl
	$(call append,$1,VHDL_SOURCES_$($2-library) += $(2))

endef

cocotb-build/Makefile: FORCE
	mkdir -p $(dir $@)
	> $@
	$(call append,$@,PWD=$$(shell pwd))
	$(call append,$@,export PYTHONPATH := $($(top-lib)-srcdir):$$(PYTHONPATH))
	$(call append,$@,SIM=ghdl)
	$(call append,$@,GHDL_ARGS += -Psim_build/)
	$(SILENT)$(foreach s,$(sources),$(call source_append_$($s-language),$@,$s))
	$(call append,$@,TOPLEVEL := $(top-entity))
	$(call append,$@,RTL_LIBRARY := $(top-lib))
	$(call append,$@,MODULE   := cocotb_entry)
	$(call append,$@,include $$(shell cocotb-config --makefiles)/Makefile.sim)


FORCE:
	@

.PHONY: FORCE
