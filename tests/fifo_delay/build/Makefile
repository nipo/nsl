top = work.tb
work-srcdir = $(SRC_DIR)/../src
tool = ghdl

include ../../../build/build.mk

$(target).vcd: input.txt output.txt

input.txt output.txt: txn_gen
	./$< $@
