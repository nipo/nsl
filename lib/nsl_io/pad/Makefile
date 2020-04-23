vhdl-sources += pad.pkg.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pad_diff_output_xc6.vhd
vhdl-sources += pad_diff_input_xc6.vhd
vhdl-sources += pad_diff_clock_input_xc6.vhd
deps += unisim.vcomponents
endif

deps += signalling.diff
