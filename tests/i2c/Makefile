top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = isim
hwdep = xilinx
target_part = xc6slx9
target_package = csg324
target_speed = -2
simulation-time = all

include ../../build/build.mk

$(target).vcd: i2c_responses.txt i2c_commands.txt

i2c_responses.txt i2c_commands.txt: txn_gen
	./$< $@
