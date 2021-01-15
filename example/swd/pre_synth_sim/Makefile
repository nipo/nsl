top = design.pre_synth_sim.testbench
design-srcdir = $(SRC_DIR)/../design
tool = ghdl
hwdep = xilinx
target_part = xc6slx9
target_package = csg324
target_speed = -2

include ../../../build/build.mk

$(target).ghw: swd_responses.txt swd_commands.txt

swd_responses.txt swd_commands.txt: txn_gen
	python3 ./$< $@
