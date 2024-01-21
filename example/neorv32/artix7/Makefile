target = hubdbg_neorv32
top = entry.fpga_io.boundary
entry-srcdir = $(SRC_DIR)/../src/entry
user_data-srcdir = $(SRC_DIR)/../src/user_data
target_part = xc7a35t
target_package = ftg256
target_speed = -2
hwdep = xilinx
tool = vivado

all: $(target)-fast.bit

include $(NSL)/build/build.mk
