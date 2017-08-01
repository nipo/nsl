vhdl-sources += clock.vhd

ifeq ($(hwdep),xilinx)
vhdl-sources += clock_output_xilinx.vhd
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
endif
else
vhdl-sources += clock_output_generic.vhd
endif
