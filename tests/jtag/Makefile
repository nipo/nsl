top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
hwdep = simulation

include ../../build/build.mk

$(target): ate_responses.txt ate_commands.txt

ate_responses.txt ate_commands.txt: txn_gen
	./$< $@
