
define list_source_do
@echo "  $1 source $2"
	
endef

define list_library_do
@echo "Library $1"
	$(foreach s,$($1-vhdl-sources),$(call list_source_do,VHDL,$s))
	$(foreach s,$($1-verilog-sources),$(call list_source_do,Verilog,$s))
	
endef

analyze elaborate simulate: list

list:
	$(foreach l,$(libraries),$(call list_library_do,$l))
