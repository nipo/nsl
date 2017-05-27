tool ?= debug

SRC_DIR := $(shell cd $(shell pwd) ; cd $(dir $(firstword $(MAKEFILE_LIST))) ; pwd)
BUILD_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)

include $(BUILD_ROOT)/enumerate.mk

$(eval $(foreach l,$(libraries),$(call library_scan,$l,$($l-srcdir))))

include $(BUILD_ROOT)/tool/$(tool).mk

ifeq ($(V),)
SILENT:=@
else
SILENT:=
endif

clean:
	rm -f $(clean-files)
	rm -rf $(clean-dirs)
