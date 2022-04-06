vhdl-sources += ddr.pkg.vhd
vhdl-sources += ddr_bus_output.vhd
vhdl-sources += ddr_bus_input.vhd

ifeq ($(hwdep),simulation)
vhdl-sources += ddr_input_simulation.vhd
vhdl-sources += ddr_output_simulation.vhd
endif

ifeq ($(hwdep),xilinx)
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += ddr_input_xc6.vhd
vhdl-sources += ddr_output_xc6.vhd
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += ddr_input_series7.vhd
vhdl-sources += ddr_output_series7.vhd
endif
deps += unisim.vcomponents
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += ddr_input_mxo2.vhd
vhdl-sources += ddr_output_mxo2.vhd
deps += machxo2.components
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += ddr_input_gowin.vhd
vhdl-sources += ddr_output_gowin.vhd
deps += gowin.components
endif

deps += nsl_io.diff
