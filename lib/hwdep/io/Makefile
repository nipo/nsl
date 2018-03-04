vhdl-sources += io.vhd
vhdl-sources += io_ddr_bus_output.vhd
vhdl-sources += io_ddr_bus_input.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += io_ddr_input_xc6.vhd
vhdl-sources += io_ddr_output_xc6.vhd
vhdl-sources += diff_clock_input.vhd
endif

deps += signalling.diff
