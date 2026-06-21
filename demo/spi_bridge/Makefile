top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
hwdep = simulation

include ../../build/build.mk

$(target): slave_transmitted.txt slave_received.txt master_cmd.txt master_rsp.txt

slave_transmitted.txt slave_received.txt master_cmd.txt master_rsp.txt: txn_gen
	./$< $@
