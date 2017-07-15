tool ?= debug
libraries += work nsl testing hwdep
work-srcdir ?= $(SRC_DIR)/src

SRC_DIR := $(shell cd $(shell pwd) ; cd $(dir $(firstword $(MAKEFILE_LIST))) ; pwd)
BUILD_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)
LIB_ROOT := $(shell cd $(BUILD_ROOT) ; cd ../lib ; pwd)

nsl-srcdir := $(LIB_ROOT)/nsl
testing-srcdir := $(LIB_ROOT)/testing
hwdep-srcdir := $(LIB_ROOT)/hwdep

define declare_source

$(1)-language := $(2)
$(1)-library := $(3)
sources += $(1)

endef

define package_scan

vhdl-sources :=
verilog-sources :=
deps := $(1)
srcdir := $$(shell cd $$(shell pwd) ; cd $$(dir $$(lastword $$(MAKEFILE_LIST))) ; pwd)

include $3/Makefile

sources :=
$$(eval $$(foreach s,$$(vhdl-sources),$$(call declare_source,$3/$$s,vhdl,$1)))
$$(eval $$(foreach s,$$(verilog-sources),$$(call declare_source,$3/$$s,verilog,$1)))

$(1).$(2)-sources := $$(sources)
$(1).$(2)-deps := $$(deps)
$(1).$(2)-library := $(1)

endef

define library_scan

vhdl-sources :=
verilog-sources :=
packages :=
deps :=

include $2/Makefile

$(1)-deps := $$(deps)
$(1)-library := $(1)

sources :=
$$(eval $$(foreach s,$$(vhdl-sources),$$(call declare_source,$2/$$s,vhdl,$1)))
$$(eval $$(foreach s,$$(verilog-sources),$$(call declare_source,$2/$$s,verilog,$1)))

$(1)-sources := $$(sources)

$$(eval $$(foreach p,$$(packages),$$(call package_scan,$1,$$p,$2/$$p)))

endef

$(eval $(foreach l,$(libraries),$(call library_scan,$l,$($l-srcdir))))

top-parts := $(subst ., ,$(top))

ifeq ($(words $(top-parts)),1)
top-library := work
top-package :=
top-entity := $(top-parts)
else
ifeq ($(words $(top-parts)),2)
ifeq ($(word 1,$(top-parts)),work)
top-library := work
top-package :=
else
top-library := work
top-package := $(word 1,$(top-parts))
endif
top-entity := $(word 2,$(top-parts))
else
ifeq ($(words $(top-parts)),3)
top-library := $(word 1,$(top-parts))
top-package := $(word 2,$(top-parts))
top-entity := $(word 3,$(top-parts))
endif
endif
endif

parts-scanned :=
sources :=

define part_scan
ifeq ($$(filter $(1),$$(parts-scanned)),)

parts-scanned += $(1)

$$(eval $$(foreach d,$$($(1)-deps),$$(call part_scan,$$(d))))

$$(info Adding $1)
sources += $$($(1)-sources)
$$($1-library)-lib-sources += $$($(1)-sources)

endif

endef

$(eval $(call part_scan,$(top-library).$(top-package)))
$(eval $(call part_scan,$(top-library)))

include $(BUILD_ROOT)/tool/$(tool).mk

ifeq ($(V),)
SILENT:=@
else
SILENT:=
endif

clean:
	rm -f $(clean-files)
	rm -rf $(clean-dirs)
