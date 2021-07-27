top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl
target_part=xc7a15t
hwdep = xilinx

include ../../build/build.mk

tb.ghw: frame.txt

frame.txt: gen
	python3 gen > frame.txt
