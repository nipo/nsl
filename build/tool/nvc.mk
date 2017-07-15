VHDL_VERSION=1993
NVC=nvc
target ?= $(top)

upper = $(shell echo "$1" | tr a-z A-Z)
elab_target := work/_WORK.$(call upper,$(target)).final.bc

simulate: $(target).lxt

.PRECIOUS: $(target).lxt

.PHONY: FORCE

$(target).lxt: $(elab_target) FORCE
	$(SILENT)$(NVC) -r $(top) --wave=$@

$(elab_target): $(foreach l,$(libraries),$l/_NVC_LIB)
	$(SILENT)$(NVC) -L. -e $(top)

define nvc_source_do
$(SILENT)$$(NVC) -L. --std=$$(VHDL_VERSION) --work=$($1-library) $2 $1 > /dev/null
	
endef

define nvc_library

$1/_NVC_LIB: $($1-lib-sources)
	rm -f $$
	$(foreach s,$($1-lib-sources),$(call nvc_source_do,$s,-a))

clean-dirs += $1/

endef

clean-files += $(target) $(target).lxt $(target).vcd

$(eval $(foreach l,$(libraries),$(call nvc_library,$l)))
