top = work.tb
work-srcdir = $(SRC_DIR)/../src
tool = isim
hwdep = xilinx
target_part = xc6slx9
target_package = csg324
target_speed = -2

include ../../../build/build.mk

$(target).vcd: slave_transmitted.txt slave_received.txt master_cmd.txt master_rsp.txt

slave_transmitted.txt slave_received.txt master_cmd.txt master_rsp.txt: txn_gen
	./$< $@
