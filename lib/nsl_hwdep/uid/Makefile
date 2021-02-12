vhdl-sources += uid.pkg.vhd

ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += uid_spartan6.vhd
deps += unisim.vcomponents
endif

deps += nsl_data.crc
