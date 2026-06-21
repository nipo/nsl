top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl

include ../../build/build.mk

$(target): dac_responses.txt dac_commands.txt

dac_responses.txt dac_commands.txt: txn_gen
	./$< $@
