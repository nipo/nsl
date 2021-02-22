vhdl-sources += uid.pkg.vhd

ifneq ($(filter xc6slx%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources += uid_series67.vhd
deps += unisim.vcomponents
endif

deps += nsl_data.crc
