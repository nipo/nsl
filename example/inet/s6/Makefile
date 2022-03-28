target = inet_test
top = work.boundary.fpga_io
work-srcdir = $(SRC_DIR)/../src
board := s6_mockup
target_part = xc6slx9
target_package = tqg144
target_speed = -2
hwdep = xilinx
tool = ise
NSL ?= ../../..

all: $(target).bit

include $(NSL)/build/build.mk
