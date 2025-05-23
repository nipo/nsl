top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
hwdep = simulation

include ../../build/build.mk

$(target).vcd: i2c_responses.txt i2c_commands.txt

i2c_responses.txt i2c_commands.txt: txn_gen
	./$< $@
