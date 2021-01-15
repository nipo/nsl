target = swd
top = design.fpga_io.swd_main
design-srcdir = $(SRC_DIR)/../design
target_part = xc6slx9
target_package = tqg144
target_speed = -2
hwdep = xilinx
tool = ise

all: $(target)-compressed.bit

../design/pnr_extract/swd_main.vhd: ise-build/$(target)-par.vhd
	cp $< $@

include ../../../build/build.mk
