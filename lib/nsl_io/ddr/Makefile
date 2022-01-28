vhdl-sources += ddr.pkg.vhd
vhdl-sources += ddr_bus_output.vhd
vhdl-sources += ddr_bus_input.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += ddr_input_xc6.vhd
vhdl-sources += ddr_output_xc6.vhd
else
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += ddr_input_series7.vhd
vhdl-sources += ddr_output_series7.vhd
endif
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
endif

deps += nsl_io.diff
