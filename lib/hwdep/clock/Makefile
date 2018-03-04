vhdl-sources += clock.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += clock_internal_7series.vhd
endif
endif

deps += hwdep.io
