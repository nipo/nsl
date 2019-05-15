vhdl-sources += clock.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
deps += unisim.vcomponents
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += clock_internal_7series.vhd
deps += unisim.vcomponents
endif
endif

deps += hwdep.io
