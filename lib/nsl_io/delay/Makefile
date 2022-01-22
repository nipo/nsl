vhdl-sources += delay.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += input_delay_fixed_xc6.vhd
vhdl-sources += output_delay_fixed_xc6.vhd
deps += nsl_hwdep.xc6_config
else
endif
deps += unisim.vcomponents
deps += nsl_data.text
endif
