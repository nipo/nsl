target ?= $(top-entity)

simulate: $(target).vcd

.PRECIOUS: $(target).vcd

.PHONY: FORCE

_NVC_STD_1993=1993
_NVC_STD_2008=08
_NVC_CF_SUFFIX_1993=93
_NVC_CF_SUFFIX_2008=08

NVC-abs := $(shell which $(NVC))
NVC-bindir := $(dir $(NVC-abs))
NVC-include := $(NVC-bindir)../include
upper-case = $(shell echo $1 | tr a-z A-Z)

clean-dirs += $(build-dir)

workdir-or = $(build-dir)/$1
workdir-map = --map=$1:$(call workdir-or,$1)
lib-index = $(call workdir-or,$1)/_index

elab-pack-path = $(call workdir-or,$1)/_$(call upper-case,$1).$(call upper-case,$2).elab.pack
has-vhdl = $(foreach f,$($1-sources),$(if $(filter vhdl,$($f-language)),t))

nvc-cmd = $(NVC) -L$(build-dir) --messages=full -M 64m $(sort $(foreach l,$($1-libdeps-unsorted),$(call workdir-map,$l))) --std=$(_NVC_STD_$($1-vhdl-version)) --work=$1:$(call workdir-or,$1) $2

define nvc-library-analyze-rules

$(call lib-index,$1): $($1-sources) $(foreach l,$($1-libdeps-unsorted),$(call lib-index,$l))
	$(SILENT)echo "[NVC] Analyzing $1"
	$(SILENT)mkdir -p $(build-dir)
	$(SILENT)$(call nvc-cmd,$1,-a --check-synthesis $($1-sources),$(if $(filter vhdl,$($f-language)),$f))

clean-dirs += $(call workdir-or,$1)

endef

define nvc-library-rules

$(call nvc-library-analyze-rules,$1)

endef

$(eval $(foreach l,$(libraries),$(call nvc-library-rules,$l)))

define nvc-plugin-compile-rule

$(build-dir)/$1.so: $($1-plugin-sources)
	$(SILENT)mkdir -p $(build-dir)
	$(SILENT)$(CC) -I$(NVC-include) -shared -fPIC -o $$@ $$<

endef

$(eval $(foreach p,$(sort $(nvc-plugin)),$(call nvc-plugin-compile-rule,$p)))

$(call elab-pack-path,$(top-lib),$(top-entity)): $(MAKEFILE_LIST) $(foreach l,$(libraries),$(if $(call has-vhdl,$l),$(call lib-index,$l)))
	$(SILENT)$(call nvc-cmd,$(top-lib),-e -j $(top-entity))

$(target): $(call elab-pack-path,$(top-lib),$(top-entity)) $(foreach l,$(nvc-plugin),$(build-dir)/$l.so)
	$(SILENT)echo '#!/bin/sh' > $@
	$(SILENT)echo '$(call nvc-cmd,$(top-lib),-r $(foreach l,$(nvc-plugin),--load $(build-dir)/$l.so) $(top-entity) $$*)' >> $@
	$(SILENT)chmod +x $@

run: $(target)
	./$(target)

$(target).vcd: $(target)
	./$(target) --wave=$@ --format=vcd --include="*" --dump-arrays=64

$(target).fst: $(target)
	./$(target) --wave=$@ --format=fst --include="*" --dump-arrays=64

clean-files += *.o $(target) $(target).vcd $(target).vcd $(target).vcd *.cf *.lst $(target) $(target).vcd.hier $(target).fst.hier $(target).fst
