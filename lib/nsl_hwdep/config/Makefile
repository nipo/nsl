vhdl-sources += config.pkg.vhd

ifneq ($(filter xc6slx%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources += config_series7.vhd
deps += unisim.vcomponents
deps += nsl_data.endian
endif
