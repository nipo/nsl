target = inet_test
top = main.boundary.fpga_io
main-srcdir = $(SRC_DIR)/src
target_part = xc7a35t
target_package = csg324
target_speed = -1
hwdep = xilinx
tool = vivado
NSL ?= ../..

all: $(target)-fast.bit

include $(NSL)/build/build.mk
