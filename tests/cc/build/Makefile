top = work.tb
work-srcdir = $(SRC_DIR)/../src
tool = isim
hwdep = xilinx
target_part = xc6slx9
target_package = csg324
target_speed = -2

include ../../../build/build.mk

$(target).vcd: cc_responses.txt cc_commands.txt

cc_responses.txt cc_commands.txt: txn_gen
	./$< $@
