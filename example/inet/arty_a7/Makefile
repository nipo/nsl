target = inet_test
top = work.boundary.fpga_io
work-srcdir = $(SRC_DIR)/../src
board := arty_a7
target_part = xc7a35t
target_package = csg324
target_speed = -1
hwdep = xilinx
tool = vivado
NSL ?= ../../..

all: $(target)-fast.bit

include $(NSL)/build/build.mk
