target = inet_test
top = work.boundary.fpga_io
work-srcdir = $(SRC_DIR)/../src
board := gw1n_9c_mockup
target_part_name = GW1N-9C
target_part = GW1N-UV9UG256C6/I5
hwdep = gowin
tool = gowin
NSL ?= ../../..

all: $(target).fs

include $(NSL)/build/build.mk
