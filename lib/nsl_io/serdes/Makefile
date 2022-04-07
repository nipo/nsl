vhdl-sources += serdes.pkg.vhd


ifeq ($(hwdep),xilinx)
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += serdes_ddr10_output_series7.vhd
vhdl-sources += serdes_ddr10_input_series7.vhd
endif
deps += unisim.vcomponents
endif

ifeq ($(hwdep),gowin)
vhdl-sources += serdes_ddr10_output_gowin.vhd
vhdl-sources += serdes_ddr10_input_gowin.vhd
deps += gowin.components
endif

ifeq ($(hwdep),simulation)
vhdl-sources += serdes_ddr10_output_simulation.vhd
vhdl-sources += serdes_ddr10_input_simulation.vhd
endif
