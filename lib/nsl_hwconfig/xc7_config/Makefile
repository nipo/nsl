ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += xc7_config.pkg.vhd

ifneq ($(filter xc7a%,$(target_part)),)
vhdl-sources += xc7_config_artix7_$(subst -,,$(target_speed)).vhd
else ifneq ($(filter xc7s%,$(target_part)),)
vhdl-sources += xc7_config_spartan7_$(subst -,,$(target_speed)).vhd
endif

deps += nsl_math.arith
deps += nsl_data.text
deps += nsl_logic.bool
endif
