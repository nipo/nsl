work-srcdir = $(SRC_DIR)/src
hwdep = xilinx
tool = vivado-ip

ip-vendor = nsl
ip-display-vendor = NSL
ip-company-url = http://www.ssji.net

target_part = xc7z020
target_package = clg400
target_speed = -1
target_families = zynq

NSL_PACKAGING_SRC_ROOT := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)
NSL_PACKAGING_ROOT := $(shell cd $(NSL_PACKAGING_SRC_ROOT)/.. ; pwd)
export NSL_PACKAGING_SRC_ROOT
export NSL_PACKAGING_ROOT

vivado_ip_repo_path = $(NSL_PACKAGING_ROOT)/vivado_repository
vivado-init-tcl += $(NSL_PACKAGING_SRC_ROOT)/vivado_init.tcl

include $(NSL_PACKAGING_SRC_ROOT)/../../build/build.mk
