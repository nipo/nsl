
define list_lib_sources_do
echo "  '$1'," >> $@
	$(SILENT)
endef

define list_lib_do
echo "$1.files = [" >> $@
	$(SILENT)$(foreach f,$($(1)-sources),$(if $(filter $($(f)-language),vhdl),$(call list_lib_sources_do,$f),))
	$(SILENT)echo "]" >> $@
	$(SILENT)
endef

analyze elaborate simulate: vhdl_ls.toml

vhdl_ls.toml:
	$(SILENT)echo '[libraries]' > $@
	$(SILENT)$(foreach l,$(libraries),$(call list_lib_do,$l))
