vhdl-sources += io.pkg.vhd
vhdl-sources += io_ddr_bus_output.vhd
vhdl-sources += io_ddr_bus_input.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += io_ddr_input_xc6.vhd
vhdl-sources += io_ddr_output_xc6.vhd
deps += unisim.vcomponents
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += io_ddr_input_mxo2.vhd
vhdl-sources += io_ddr_output_mxo2.vhd
deps += machxo2.components
endif

vhdl-sources += io_clock_output.vhd

deps += signalling.diff
