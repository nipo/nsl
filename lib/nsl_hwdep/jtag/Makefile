vhdl-sources += jtag.pkg.vhd
vhdl-sources += jtag_reg.vhd
vhdl-sources += jtag_inbound_fifo.vhd
vhdl-sources += jtag_outbound_fifo.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += jtag_tap_register_spartan6.vhd
deps += unisim.vcomponents
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += jtag_tap_register_7series.vhd
deps += unisim.vcomponents
endif
endif
