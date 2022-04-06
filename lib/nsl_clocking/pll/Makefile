vhdl-sources += pll.pkg.vhd

ifeq ($(hwdep),simulation)
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

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += pll_basic_gowin.vhd
deps += nsl_data.text
deps += nsl_hwdep.gowin_config
deps += gowin.components
endif

ifneq ($(filter xc6slx%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources := $(filter-out pll_basic_simulation.vhd,$(vhdl-sources))

vhdl-sources += pll_config_series67.vhd
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pll_config_series6.vhd
deps += nsl_hwdep.xc6_config
else ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += pll_config_series7.vhd
deps += nsl_hwdep.xc7_config
endif

vhdl-sources += pll_basic_series67.vhd
deps += unisim.vcomponents
deps += nsl_math.arith
deps += nsl_data.text
deps += nsl_logic.bool
endif
