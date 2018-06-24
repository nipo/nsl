tool ?= debug
work-srcdir ?= $(SRC_DIR)/src
source-types += vhdl verilog

SRC_DIR := $(shell cd $(shell pwd) ; cd $(dir $(firstword $(MAKEFILE_LIST))) ; pwd)
BUILD_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)
LIB_ROOT := $(shell cd $(BUILD_ROOT) ; cd ../lib ; pwd)

define declare_source

$1-language := $2
$1-library := $3
_tmp-sources += $1

endef

define source-list-cleanup

$1-sources :=

endef

define package_scan

#$$(info Scanning package $1.$2)


$(foreach l,$(source-types),$(call source-list-cleanup,$l))
deps := $1
pkg := $1.$2
srcdir := $$(shell cd $$(shell pwd) ; cd $$(dir $$(lastword $$(MAKEFILE_LIST))) ; pwd)

include $3/Makefile

_tmp-sources :=
$(foreach l,$(source-types),$$(eval $$(foreach s,$$($l-sources),$$(call declare_source,$3/$$s,$l,$1))))

$$(pkg)-sources := $$(_tmp-sources)
$$(pkg)-deps := $$(deps)
$$(pkg)-library := $1

endef

libraries :=

library_scan = $(if $(filter $1,$(libraries)),,$(call _library_scan,$1))

define _library_scan

#$$(info Scanning library $1)

libraries += $1

srcdir := $($1-srcdir)
ifeq ($$(srcdir),)
srcdir := $(LIB_ROOT)/$1
endif

#$$(info srcdir: $$(srcdir))

$(foreach l,$(source-types),$(call source-list-cleanup,$l))
packages :=
deps :=

include $$(srcdir)/Makefile

$1-deps := $$(deps)
$1-library := $1

_tmp-sources :=
$(foreach l,$(source-types),$$(eval $$(foreach s,$$($l-sources),$$(call declare_source,$$(srcdir)/$$s,$l,$1))))

$1-sources := $$(_tmp-sources)

$$(eval $$(foreach p,$$(packages),$$(call package_scan,$1,$$p,$$(srcdir)/$$p)))

endef

top-parts := $(subst ., ,$(top))
library_name = $(word 1,$(subst ., ,$1))

ifeq ($(words $(top-parts)),1)
top-lib := work
top-package :=
top-entity := $(top-parts)
else
ifeq ($(words $(top-parts)),2)
top-lib := $(word 1,$(top-parts))
top-package := 
top-entity := $(word 2,$(top-parts))
else
ifeq ($(words $(top-parts)),3)
top-lib := $(word 1,$(top-parts))
top-package := $(word 2,$(top-parts))
top-entity := $(word 3,$(top-parts))
endif
endif
endif

parts-scanned :=
sources :=

define part_scan
#$$(info $2 Scanning part $1, done=$$(parts-scanned))

ifeq ($$(filter $1,$$(parts-scanned)),)

$$(eval $$(foreach l,$$(sort $$(foreach ll,$$($1-deps),$$(call library_name,$$(ll)))),$$(call library_scan,$$l)))

parts-scanned += $1

#$$(info $2 $1 - lib deps: $$(sort $$(foreach ll,$$($1-deps),$$(call library_name,$$(ll) $1))))
$$(eval $$(foreach d,$$($1-deps),$$(call part_scan,$$(d),_$2)))

$$($1-library)-lib-sources += $$($1-sources)
sources += $$($1-sources)

#$$(info $2 $1 - sources: $$($1-sources))

endif

endef

define lib_deps_calc

$(1)-lib-deps := $(sort $(filter-out $1,$(foreach p,$(filter $1%,$(parts-scanned)),$(foreach d,$($p-deps),$($d-library)))))

endef

include $(BUILD_ROOT)/tool/$(tool).mk

$(eval $(call library_scan,$(top-lib)))
$(eval $(call part_scan,$(top-lib)$(if $(top-package),.$(top-package),),))
$(eval $(foreach l,$(libraries),$(call lib_deps_calc,$l)))

ifeq ($(V),)
SILENT:=@
else
SILENT:=
endif

clean:
	rm -f $(sort $(clean-files))
	rm -rf $(clean-dirs)
