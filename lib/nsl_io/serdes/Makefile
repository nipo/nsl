vhdl-sources += serdes.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += serdes_ddr10_output_series7.vhd
vhdl-sources += serdes_ddr10_input_series7.vhd
endif
deps += unisim.vcomponents
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += serdes_ddr10_output_gowin.vhd
vhdl-sources += serdes_ddr10_input_gowin.vhd
deps += gowin.components
endif
