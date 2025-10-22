tool ?= debug
work-srcdir ?= $(SRC_DIR)/src
source-types += vhdl verilog ngc bd constraint
target-usage ?= synthesis

.SUFFIXES:

SRC_DIR := $(shell cd $(shell pwd) ; cd $(dir $(firstword $(MAKEFILE_LIST))) ; pwd)
build-dir = $(SRC_DIR)/$(tool)-build

BUILD_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)
NSL_ROOT := $(shell cd $(BUILD_ROOT) ; cd ../lib ; pwd)
HDL_LIBRARY_PATH += $(NSL_ROOT)
TOOL_ROOT := $(BUILD_ROOT)/tool/

PYTHONPATH=$(BUILD_ROOT)/../python

export PYTHONPATH

-include $(TOOL_ROOT)/$(tool)-pre.mk

# Uniq without reordering (unlike sort), keeping first entry
# <word list>
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))

# Uniq without reordering (unlike sort), keeping last entry
# <word list>
runiq = $(if $1,$(call runiq,$(filter-out $(lastword $1),$1)) $(lastword $1))

# <package list> <package list>
# Returns deep subtree from $1's dependencies, excluding those in $2
deep_deps = $(if $(filter $1,$2),,$1 $(foreach p,$($1-deps-unsorted),$(call deep_deps,$p,$1 $2)))

# <word list> <word list>
# Returns $1 with only words in $2, without changing $1 order
filter-many = $(foreach w,$1,$(filter $w,$2))

# <word list> <word list>
# Returns $1 without words in $2, without changing $1 order
filter-out-many = $(if $2,$(call filter-out-many,$(filter-out $(firstword $2),$1),$(filter-out $(firstword $2),$2)),$1)

# <package_name or library_name>
# Retruns a full package name (with ._bare if needed)
pkg-full-name = $(if $(filter $(firstword $(subst ., ,$1)),$1),$1._bare,$1)

# <package_name>
# Retruns a short package name (without ._bare if library)
user-package-name = $(subst ._bare,,$1)

# <filename> <language> <library> <package>
# Export source file with its attributes
define declare-source
ifneq ($(nsl-build-debug),)
$$(info declare-source lang $2 pkg $3.$4 src $1)
endif

$1-language := $2
$1-library := $3
$1-package := $3.$4
$3.$4-sources += $1

endef

# <language>
# Reset source list
define source-list-cleanup
$1-sources :=

endef

# <library> <package> <path> <indent>
# Ingress directory $1.$2 from directory $3 ($2 may be "_bare")
define directory-ingress
ifneq ($(nsl-build-debug),)
$$(info $4 Parsing $1.$2 from $3/Makefile)
endif

$(foreach l,$(source-types),$(call source-list-cleanup,$l))
deps :=
srcdir := $3
$1.$2-library := $1
$1.$2-package := $2
$1.$2-sub-packages :=
$1-all-packages += $1.$2
packages :=
vhdl-version :=

$(if $(wildcard $3/Makefile),,$(warning $(call user-package-name,$(notdir $4)) references undefined $(call user-package-name,$1.$2)))

include $3/Makefile

$1.$2-vhdl-version := $$(vhdl-version)
$1.$2-vhdl-sources := $$(filter %.pkg.vhd,$$($1.$2-vhdl-sources)) $$(filter-out %.pkg.vhd,$$($1.$2-vhdl-sources))
$1.$2-sub-packages := $$(sort $$(packages))
$$(eval $$(foreach l,$$(sort $$(source-types)),$$(foreach s,$$($$l-sources),$$(call declare-source,$$(if $$(filter /%,$$s),$$s,$3/$$s),$$l,$1,$2))))

$1.$2-deps-unsorted := $$(foreach p,$$(deps),$$(call pkg-full-name,$$p))
$$(eval $$(call ensure-package-deps-parsed,$1.$2,$4/$1.$2))

endef

# <library> <package> <srcdir> <indent>
# Ingress package $1.$2 from directory $3
define package-ingress
ifneq ($(nsl-build-debug),)
$$(info $4 Scanning package $1.$2)
endif

$(call directory-ingress,$1,$2,$3,$4)
$$(if $$($1.$2-vhdl-version),$$(warning Package $1.$2 tries to set VHDL version, ignored))
$1.$2-vhdl-version :=

endef

# <library> <indent>
# Ingress library $1 if not already in $(all-libraries)
library-parse = $(if $(filter $1,$(all-libraries)),,$(call _library-parse,$1,$2))
define _library-parse
ifneq ($(nsl-build-debug),)
$$(info Adding library $1 in $($1-srcdir))
endif

all-libraries += $1

$(call directory-ingress,$1,_bare,$($1-srcdir),$2)

ifneq ($(nsl-build-debug),)
$$(info $1 **** packages: $$($1._bare-sub-packages))
endif

$1-vhdl-version := $$(if $$($1._bare-vhdl-version),$$($1._bare-vhdl-version),1993)
$1._bare-vhdl-version :=
$$(eval $$(foreach p,$$($1._bare-sub-packages),$$(call package-ingress,$1,$$p,$$($1-srcdir)/$$p,$2)))
$$(eval $$(call ensure-package-deps-parsed,$1._bare,$2))

endef

# <package_name> <indent>
# Ingress packages from $1 if they dont already appear in $(package-deps-parsed-list)
ensure-package-deps-parsed = $(if $(filter $1,$(package-deps-parsed-list)),,$(call _ensure-package-deps-parsed,$1,$2))
define _ensure-package-deps-parsed
ifneq ($(nsl-build-debug),)
$$(info $2 Ensuring deps of $1 are parsed, done=$(package-deps-parsed-list))
endif

package-deps-parsed-list += $1
$$(eval $$(foreach l,$$(sort $$(foreach ll,$$($1-deps-unsorted),$$(call library_name,$$(ll)))),$$(call library-parse,$$l,$2)))

endef

# <package_names> <package_names>
# $1 a set of packages
# $2 a set of packages that are done
# -> return packages with no deps first
only-pkg-nodeps = $(sort $(foreach i,$1,$(if $(call filter-out-many,$($i-intradeps-unsorted),$2 $i),,$i)))
not-empty-or-circular-dep = $(if $1,$1,$(error Circular dependency within $2, $3))
pkg-donedeps-first = $(if $1,$(call not-empty-or-circular-dep,$(call only-pkg-nodeps,$1,$2),$1,$2) $(call pkg-donedeps-first,$(call filter-out-many,$1,$2 $(call only-pkg-nodeps,$1,$2)),$2 $(call only-pkg-nodeps,$1,$2)))

# <libraries> <libraries>
# $1 a set of libs
# $2 a set of libs that are done
# -> return libs with empty set of undone deps, recurse of others
only-lib-nodeps = $(sort $(foreach i,$1,$(if $(call filter-out-many,$($i-libdeps-unsorted),$2 $i),,$i)))
lib-donedeps-first = $(if $1,$(call not-empty-or-circular-dep,$(strip $(call only-lib-nodeps,$1,$2)) $(call lib-donedeps-first,$(call filter-out-many,$1,$2 $(call only-lib-nodeps,$1,$2)),$2 $(call only-lib-nodeps,$1,$2)),$2))

# <package_name>
# For a package, calculates
#  all packages deps,
#  intra-library package deps.
define package_deep_deps_calc

ifneq ($(nsl-build-debug),)
$$(info Calculating deps for: $1)
endif

$1-deepdeps-unsorted := $(filter-out $1,$(sort $(call deep_deps,$1)))

ifneq ($(nsl-build-debug),)
$$(info Deepdeps for $1 done)
endif

$1-intradeps-unsorted := $(sort $(filter $($1-library).%,$($1-deps-unsorted)))

ifneq ($(nsl-build-debug),)
$$(info Intradeps for $1 done)
endif

endef

# <library>
# For a library, calculates
#  internal package order (using only enabled packages)
define lib_enable_calc
$1-enabled-packages := $(sort $(call filter-many,$($1-all-packages),$(enabled-packages)))

endef

# <library>
# For a library, calculates
#  all packages deps for a given library,
#  other libraries for a given library
define lib_deps_calc
$1-packages := $(call pkg-donedeps-first,$($1-enabled-packages))
$(1)-deps-unsorted := $(filter-out $1,$(sort $(foreach p,$($1-enabled-packages),$($p-deps-unsorted))))
$(1)-libdeps-unsorted := $(filter-out $1,$(sort $(filter-out $1,$(foreach t,$(foreach p,$($1-enabled-packages),$($p-deepdeps-unsorted)),$($t-library)))))

endef

# <library>
# For a library, calculates
#  ordered source set
define lib_build_calc
ifneq ($(nsl-build-debug),)
$$(info $1 sources: $(foreach p,$($1-packages),$($p-sources)))
endif
$1-sources := $(call uniq,$(foreach p,$($1-packages),$($p-sources)))

endef

# <language>
define source_type_gather
all-$1-sources := $(foreach f,$(sources),$(if $(filter $1,$($f-language)),$f))

endef

# <package_name> <libraries>
# Removes libraries in $2 from references in package $1
define exclude-libs-pkg
$1-deps-unsorted := $(call filter-out-many,$($1-deps-unsorted),$2)
$1-deepdeps-unsorted := $(call filter-out-many,$($1-deepdeps-unsorted),$2)

endef

# <library> <libraries>
# Removes libraries in $2 from references in lib $1
define exclude-libs-lib
$1-libdeps-unsorted := $(sort $(call filter-out-many,$($1-libdeps-unsorted),$2 $1))
$1-deps-unsorted := $(sort $(call filter-out-many,$($1-libdeps-unsorted),$2 $1))
$(foreach p,$($1-packages),$(call exclude-libs-pkg,$p,$(foreach l,$2,$($l-all-packages))))

endef

# Public backend API
# <libraries>
# Remove multiple libraries from build variables
exclude-libs = $(eval $(call exclude-libs-internal,$1))
define exclude-libs-internal
$(eval $(call exclude-libs-internal-1,$1))
$(eval $(call exclude-libs-internal-2,$1))
$(eval $(call exclude-libs-internal-3))

endef

define exclude-libs-internal-1
libraries := $(call uniq,$(call filter-out-many,$(libraries),$1))

endef

define exclude-libs-internal-2
$(foreach l,$(libraries),$(call exclude-libs-lib,$l,$1))
endef

define exclude-libs-internal-3
sources := $(foreach l,$(libraries),$($l-sources))
$(foreach t,$(source-types),$(call source_type_gather,$t))

endef


####
## We are ready to process
####

## Compute topcell full name, library, package (_bare if not), entity name
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

## Reset variables
all-libraries :=
package-deps-parsed-list :=

## Start reading top library, it will recurse down
ifneq ($(nsl-build-debug),)
$(info Starting from top library)
endif

# This is responsible for declaring all $(lib)-srcdir of one lib
hdl-library-path-scan = $(if $(wildcard $2/Makefile),$(eval $1-srcdir := $2),)

# This is responsible for declaring all $(lib)-srcdir of all libs
hdl-library-path-scan-all = $(foreach l,$(shell find "$1" -maxdepth 1 -type d -print | sed "s,$1/,,"),$(call hdl-library-path-scan,$l,$1/$l))

$(eval $(foreach l,$(HDL_LIBRARY_PATH),$(call hdl-library-path-scan-all,$l)))
$(eval $(call library-parse,$(top-lib),$(top-lib)))

ifneq ($(nsl-build-debug),)
$(info Done parsing libraries, calculating dependencies)
endif

## Calculate all packages deps
all-packages := $(foreach l,$(all-libraries),$($l-all-packages))

ifneq ($(nsl-build-debug),)
$(info all-packages: $(all-packages))
endif

$(eval $(foreach p,$(all-packages),$(call package_deep_deps_calc,$p)))

## This is the set of packages we'll build
enabled-packages := $(top-package) $($(top-package)-deepdeps-unsorted)

ifneq ($(nsl-build-debug),)
$(info Enabled: $(enabled-packages))
endif

## Dependency-dependent reordering
$(eval $(foreach l,$(all-libraries),$(call lib_enable_calc,$l)))
$(eval $(foreach l,$(all-libraries),$(call lib_deps_calc,$l)))

## Enabled libraries and sources
$(eval $(foreach l,$(all-libraries),$(call lib_build_calc,$l)))

ifneq ($(nsl-build-debug),)
$(info Done calculating build order)
endif

ifneq ($(nsl-build-debug),)
$(info Calculating lib order)
endif

libraries := $(call uniq,$(call lib-donedeps-first,$(call uniq,$(all-libraries)),))

ifneq ($(nsl-build-debug),)
$(info Libraries in order: $(libraries))
endif

sources := $(foreach l,$(libraries),$($l-sources))
$(eval $(foreach t,$(source-types),$(call source_type_gather,$t)))

ifeq ($(V),)
SILENT:=@
else
SILENT:=
endif

include $(TOOL_ROOT)/$(tool).mk

clean:
	$(SILENT)rm -f $(sort $(clean-files))
	$(SILENT)rm -rf $(clean-dirs)
