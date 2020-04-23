vhdl-sources += clock.pkg.vhd
vhdl-sources += clock_output_diff_to_se.vhd
vhdl-sources += clock_output_se_to_se.vhd
deps += nsl_io.diff
deps += nsl_io.ddr

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += clock_input_diff_to_diff_xc6.vhd
deps += unisim.vcomponents
else
vhdl-sources += clock_input_diff_to_diff_generic.vhd
endif
