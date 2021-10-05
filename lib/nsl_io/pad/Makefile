vhdl-sources += pad.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += pad_diff_output_xc.vhd
vhdl-sources += pad_tmds_output_xc.vhd
vhdl-sources += pad_tmds_input_xc.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pad_diff_input_xc6.vhd
vhdl-sources += pad_diff_clock_input_xc6.vhd
endif

ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += pad_diff_input_xc7.vhd
vhdl-sources += pad_diff_clock_input_xc7.vhd
endif

deps += unisim.vcomponents
endif

deps += nsl_io.diff
