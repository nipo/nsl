work-srcdir = $(SRC_DIR)/src
hwdep = xilinx
tool = vivado-ip

ip-vendor = nsl
ip-display-vendor = NSL
ip-company-url = www.ssji.net

target_part = xc7z020
target_package = clg400
target_speed = -1
target_families = zynq

curdir := $(shell cd $(shell pwd) ; cd $(dir $(lastword $(MAKEFILE_LIST))) ; pwd)

vivado_ip_repo_path = $(curdir)/ip_repo

include $(curdir)/../../build/build.mk
