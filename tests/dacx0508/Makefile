top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = isim

include ../../build/build.mk

$(target).ghw: tb dac_responses.txt dac_commands.txt

dac_responses.txt dac_commands.txt: txn_gen
	./$< $@
