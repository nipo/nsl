top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
hwdep = simulation

include ../../build/build.mk

$(target): frame.txt frame_hdlc.txt

frame.txt frame_hdlc.txt: txn_gen
	./$< $@
