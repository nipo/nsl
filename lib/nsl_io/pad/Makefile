vhdl-sources += pad.pkg.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pad_diff_output_xc6.vhd
vhdl-sources += pad_diff_input_xc6.vhd
vhdl-sources += pad_diff_clock_input_xc6.vhd
deps += unisim.vcomponents
endif

ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += pad_diff_output_xc7.vhd
vhdl-sources += pad_diff_input_xc7.vhd
vhdl-sources += pad_diff_clock_input_xc7.vhd
deps += unisim.vcomponents
endif

deps += nsl_io.diff
