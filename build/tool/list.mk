
define list_source_do
echo "  $($1-language) in $($1-library): $1"
	$(SILENT)
endef

analyze elaborate simulate: list

list:
	$(SILENT)$(foreach s,$(sources),$(call list_source_do,$s))
