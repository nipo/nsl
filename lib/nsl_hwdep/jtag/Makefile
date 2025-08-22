vhdl-sources += jtag.pkg.vhd
vhdl-sources += jtag_reg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += jtag_tap_register_spartan6.vhd
vhdl-sources += jtag_user_tap_spartan6.vhd
deps += unisim.vcomponents
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += jtag_tap_register_7series.vhd
vhdl-sources += jtag_user_tap_series7.vhd
deps += unisim.vcomponents
endif
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += jtag_user_tap_gowin.vhd
endif
