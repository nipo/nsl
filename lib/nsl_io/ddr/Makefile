vhdl-sources += ddr.pkg.vhd
vhdl-sources += ddr_bus_output.vhd
vhdl-sources += ddr_bus_input.vhd
vhdl-sources += ddr_bus_output_tristated.vhd

ifeq ($(hwdep),simulation)
vhdl-sources += ddr_input_simulation.vhd
vhdl-sources += ddr_output_simulation.vhd
vhdl-sources += ddr_output_tristated_simulation.vhd
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
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += ddr_input_mxo2.vhd
vhdl-sources += ddr_output_mxo2.vhd
deps += machxo2.components
endif

ifneq ($(filter lattice-ecp5,$(hwdep)),)
vhdl-sources += ddr_output_ecp5.vhd
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += ddr_input_gowin.vhd
vhdl-sources += ddr_output_gowin.vhd
vhdl-sources += ddr_output_tristated_gowin.vhd
endif

ifneq ($(filter altera,$(hwdep)),)
ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += ddr_input_agilex5.vhd
vhdl-sources += ddr_output_agilex5.vhd
endif
ifneq ($(filter 10CL%,$(target_part)),)
vhdl-sources += ddr_output_cyclone10lp.vhd
endif
endif

deps += nsl_io.diff
deps += nsl_io.io
