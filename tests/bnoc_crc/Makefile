top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
hwdep = xilinx
target_part = xc6slx9
target_package = csg324
target_speed = -2

include ../../build/build.mk

$(target).ghw: dataset.txt dataset_crc.txt

dataset.txt dataset_crc.txt: txn_gen
	./$< $@
