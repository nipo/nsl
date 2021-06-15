vhdl-sources += pll.pkg.vhd

ifeq ($(target-usage),simulation)
vhdl-sources += pll_basic_simulation.vhd
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += pll_basic_ice40.vhd
deps += nsl_data.text
deps += sb_ice
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += pll_basic_machxo2.vhd
deps += nsl_data.text
deps += machxo2
endif

ifneq ($(filter xc6slx%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources := $(filter-out pll_basic_simulation.vhd,$(vhdl-sources))

vhdl-sources += pll_config_series67.vhd
ifneq ($(filter xc6s%,$(target_part)),)
vhdl-sources += pll_config_spartan6_$(subst -,,$(target_speed)).vhd
else ifneq ($(filter xc7a%,$(target_part)),)
vhdl-sources += pll_config_artix7_$(subst -,,$(target_speed)).vhd
else ifneq ($(filter xc7s%,$(target_part)),)
vhdl-sources += pll_config_spartan7_$(subst -,,$(target_speed)).vhd
endif

vhdl-sources += pll_basic_series67.vhd
deps += unisim.vcomponents
deps += nsl_math.arith
deps += nsl_data.text
deps += nsl_logic.bool
endif
