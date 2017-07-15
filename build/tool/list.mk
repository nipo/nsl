
define list_source_do
$(SILENT)echo "  $($1-language) in $($1-lib): $1"
	
endef

analyze elaborate simulate: list

list:
	$(foreach s,$(sources),$(call list_source_do,$s))
