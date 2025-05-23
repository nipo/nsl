top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl

include ../../build/build.mk

tb.ghw: smi_responses.txt smi_commands.txt

smi_responses.txt smi_commands.txt: txn_gen
	./$< $@
