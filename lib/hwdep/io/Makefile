vhdl-sources += io.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += diff_output_pad_xc6.vhd
vhdl-sources += diff_input_pad_xc6.vhd
endif

deps += signalling.diff
