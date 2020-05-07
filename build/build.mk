tool ?= debug
work-srcdir ?= $(SRC_DIR)/src
source-types += vhdl verilog ngc bd constraint

uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))
runiq = $(if $1,$(call runiq,$(filter-out $(lastword $1),$1)) $(lastword $1))
deep_deps = $(if $(filter $1,$2),,$1 $(foreach p,$($1-deps-unsorted),$(call deep_deps,$p,$1 $2)))
filter-many = $(foreach w,$1,$(filter $w,$2))
filter-out-many = $(if $2,$(call filter-out-many,$(filter-out $(firstword $2),$1),$(filter-out $(firstword $2),$2)),$1)

pkg-full-name = $(if $(filter $(firstword $(subst ., ,$1)),$1),$1._bare,$1)

.SUFFIXES:

SRC_DIR := $(shell cd $(shell pwd) ; cd $(dir $(firstword $(MAKEFILE_LIST))) ; pwd)
BUILD_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)
LIB_ROOT := $(shell cd $(BUILD_ROOT) ; cd ../lib ; pwd)

PYTHONPATH=$(BUILD_ROOT)/../python

export PYTHONPATH

define declare_source

$1-language := $2
$1-library := $3
$1-package := $3.$4
_tmp-sources += $1

endef

define source-list-cleanup

$1-sources :=

endef

define package_scan

#$$(info Scanning package $1.$2)

$(foreach l,$(source-types),$(call source-list-cleanup,$l))
deps :=
srcdir := $$(shell cd $$(shell pwd) ; cd $$(dir $$(lastword $$(MAKEFILE_LIST))) ; pwd)
vhdl-version :=

include $3/Makefile

$$(if $$(vhdl-version),$$(warning Package $1.$2 tries to set VHDL version, ignored))
_tmp-sources :=
source-types := $$(sort $$(sources-types))
$(foreach l,$(source-types),$$(eval $$(foreach s,$$($l-sources),$$(call declare_source,$3/$$s,$l,$1,$2))))

$1.$2-sources := $$(_tmp-sources)
$1.$2-deps-unsorted := $$(foreach p,$$(deps),$$(call pkg-full-name,$$p))
$1.$2-library := $1
$1-all-packages += $1.$2

endef

libraries :=

library_scan = $(if $(filter $1,$(libraries)),,$(call _library_scan,$1))

define _library_scan

#$$(info Scanning library $1)

libraries += $1

vhdl-version := 93
$1-all-packages := $1._bare
srcdir := $($1-srcdir)
ifeq ($$(srcdir),)
srcdir := $(LIB_ROOT)/$1
endif

#$$(info srcdir: $$(srcdir))

$(foreach l,$(source-types),$(call source-list-cleanup,$l))
packages :=
deps :=

include $$(srcdir)/Makefile

$1._bare-deps-unsorted := $$(deps)
$1._bare-library := $1

_tmp-sources :=
$(foreach l,$(source-types),$$(eval $$(foreach s,$$($l-sources),$$(call declare_source,$$(srcdir)/$$s,$l,$1))))

$1-vhdl-version := $$(vhdl-version)
$1._bare-sources := $$(_tmp-sources)
$1._bare-sources := $$(_tmp-sources)

$$(eval $$(foreach p,$$(packages),$$(call package_scan,$1,$$p,$$(srcdir)/$$p)))

endef

top-parts := $(subst ., ,$(top))
library_name = $(word 1,$(subst ., ,$1))

ifeq ($(words $(top-parts)),1)
top-lib := work
top-package-name := _bare
top-entity := $(top-parts)
else
ifeq ($(words $(top-parts)),2)
top-lib := $(word 1,$(top-parts))
top-package-name := _bare
top-entity := $(word 2,$(top-parts))
else
ifeq ($(words $(top-parts)),3)
top-lib := $(word 1,$(top-parts))
top-package-name := $(word 2,$(top-parts))
top-entity := $(word 3,$(top-parts))
endif
endif
endif
top-package := $(top-lib).$(top-package-name)

parts-scanned :=
sources :=

define part_scan
#$$(info $2 Scanning part $1, done=$$(parts-scanned))

ifeq ($$(filter $1,$$(parts-scanned)),)

$$(eval $$(foreach l,$$(sort $$(foreach ll,$$($1-deps-unsorted),$$(call library_name,$$(ll)))),$$(call library_scan,$$l)))

parts-scanned += $1

$$(eval $$(foreach d,$$($1-deps-unsorted),$$(call part_scan,$$(d),_$2)))

$$($1-library)-lib-sources += $$($1-sources)
sources += $$($1-sources)

#$$(info $2 $1 - sources: $$($1-sources))

endif

endef

# 1 a set of packages
# 2 a set of packages that are done
# -> return packages with no deps first
only-pkg-nodeps = $(sort $(foreach i,$1,$(if $(call filter-out-many,$($i-intradeps-unsorted),$2 $i),,$i)))
not-empty-or-circular-dep = $(if $1,$1,$(error Circular dependency within $2))
pkg-donedeps-first = $(if $1,$(call not-empty-or-circular-dep,$(call only-pkg-nodeps,$1,$2),$1) $(call pkg-donedeps-first,$(call filter-out-many,$1,$2 $(call only-pkg-nodeps,$1,$2)),$2 $(call only-pkg-nodeps,$1,$2)))

# 1 a set of libs
# 2 a set of libs that are done
# -> return libs with empty set of undone deps, recurse of others
only-lib-nodeps = $(sort $(foreach i,$1,$(if $(call filter-out-many,$($i-libdeps-unsorted),$2 $i),,$i)))
lib-donedeps-first = $(if $1,$(call not-empty-or-circular-dep,$(strip $(call only-lib-nodeps,$1,$2)) $(call lib-donedeps-first,$(call filter-out-many,$1,$2 $(call only-lib-nodeps,$1,$2)),$2 $(call only-lib-nodeps,$1,$2))))

# For a package, calculates
#  all packages deps,
#  intra-library package deps.
define package_deep_deps_calc
$1-deepdeps-unsorted := $(filter-out $1,$(sort $(call deep_deps,$1)))
$1-intradeps-unsorted := $(sort $(filter $($1-library).%,$($1-deps-unsorted)))

endef

# For a library, calculates
#  internal package order (using only enabled packages)
define lib_enable_calc
$1-enabled-packages := $(sort $(call filter-many,$($1-all-packages),$(enabled-packages)))

endef

# For a library, calculates
#  all packages deps for a given library,
#  other libraries for a given library
define lib_deps_calc
$1-packages := $(call pkg-donedeps-first,$($1-enabled-packages))
$(1)-deps-unsorted := $(sort $(foreach p,$($1-enabled-packages),$($p-deps-unsorted)))
$(1)-libdeps-unsorted := $(sort $(filter-out $1,$(foreach t,$(foreach p,$($1-enabled-packages),$($p-deepdeps-unsorted)),$($t-library))))

endef

# For a library, calculates
#  ordered source set
define lib_build_calc
$1-sources := $(foreach p,$($1-packages),$($p-sources))

endef

define source_type_gather
all-$1-sources := $(foreach f,$(sources),$(if $(filter $1,$($f-language)),$f))

endef

# args : package_name, excluded_packages
define exclude-libs-pkg

$1-deepdeps-unsorted := $(call filter-out-many,$($1-deepdeps-unsorted),$2)
$1-intradeps-unsorted := $(call filter-out-many,$($1-intradeps-unsorted),$2)

endef

# args : lib_name, excluded_libs
define exclude-libs-lib

$1-libdeps-unsorted := $(call filter-out-many,$($1-libdeps-unsorted),$2)
$1-deps-unsorted := $(call filter-out-many,$($1-libdeps-unsorted),$2)
$(foreach p,$($1-packages),$(call exclude-libs-pkg,$p,$(foreach l,$2,$($l-all-packages))))

endef

# args : lib_names
define exclude-libs-internal

sources := $(foreach l,$(call filter-out-many,$(libraries),$1),$($l-sources))
libraries := $(call filter-out-many,$(libraries),$1)
$(foreach l,$(libraries),$(call exclude-libs-lib,$l,$1))

endef

# Public backend API
# args : lib_names to remove from build and deps
exclude-libs = $(eval $(call exclude-libs-internal,$1))

####
## We are ready to process
####

## Start reading top library
$(eval $(call library_scan,$(top-lib)))
## Recurse down to all libraries
$(eval $(call part_scan,$(top-package),))
## Calculate all packages deps
all-packages := $(foreach l,$(libraries),$($l-all-packages))
$(eval $(foreach p,$(all-packages),$(call package_deep_deps_calc,$p)))

enabled-packages := $(top-package) $($(top-package)-deepdeps-unsorted)

## Dependency reordering
$(eval $(foreach l,$(libraries),$(call lib_enable_calc,$l)))
$(eval $(foreach l,$(libraries),$(call lib_deps_calc,$l)))
$(eval $(foreach l,$(libraries),$(call lib_build_calc,$l)))
$(eval $(foreach t,$(source-types),$(call source_type_gather,$t)))
libraries := $(call lib-donedeps-first,$(libraries),)

## All sources
sources := $(foreach l,$(libraries),$($l-sources))


TOOL_ROOT := $(BUILD_ROOT)/tool/
include $(TOOL_ROOT)/$(tool).mk

ifeq ($(V),)
SILENT:=@
else
SILENT:=
endif

clean:
	rm -f $(sort $(clean-files))
	rm -rf $(clean-dirs)
