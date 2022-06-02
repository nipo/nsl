target = hubdbg_neorv32
top = entry.fpga_io.boundary
entry-srcdir = $(SRC_DIR)/../entry
neorv32-srcdir = $(SRC_DIR)/../neorv32
target_part = xc7a35t
target_package = ftg256
target_speed = -2
hwdep = xilinx
tool = vivado

all: $(target)-fast.bit

include $(NSL)/build/build.mk
