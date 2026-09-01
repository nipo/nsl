ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += xc6_config.pkg.vhd

ifneq ($(filter xc6s%,$(target_part)),)
vhdl-sources += xc6_config_spartan6_$(subst -,,$(target_speed)).vhd
endif

deps += nsl_math.arith
deps += nsl_data.text
deps += nsl_logic.bool
endif
