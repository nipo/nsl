vhdl-sources += reset.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += reset_at_startup_xc.vhd
deps += unisim.vcomponents
endif
