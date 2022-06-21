top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl

include ../../build/build.mk

tb.ghw: swd_responses.txt swd_commands.txt

swd_responses.txt swd_commands.txt: txn_gen
	./$< $@
