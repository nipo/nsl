target = inet_test
top = work.boundary.fpga_io
work-srcdir = $(SRC_DIR)/../src
board := gw2a_18c_mockup
target_part_name = GW2A-18C
target_part = GW2A-LV18QN88C8/I7
hwdep = gowin
tool = gowin
NSL ?= ../../..

all: $(target).fs

include $(NSL)/build/build.mk
