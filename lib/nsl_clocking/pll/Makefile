vhdl-sources += pll.pkg.vhd
deps += nsl_data.text
deps += nsl_synthesis.assertion

ifeq ($(hwdep),simulation)
vhdl-sources += pll_basic_simulation.vhd
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_simulation.vhd
vhdl-sources += pll_multi_simulation.vhd
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_ice40.vhd
vhdl-sources += pll_multi_ice40.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_data.text
deps += sb_ice.components
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += pll_basic_machxo2.vhd
deps += nsl_data.text
deps += machxo2
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_gowin.vhd
vhdl-sources += pll_multi_gowin.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_data.text
deps += nsl_hwconfig.gowin_config
deps += nsl_synthesis.logging
deps += nsl_clocking.distribution
endif

ifneq ($(filter xc6slx%,$(target_part))$(filter xc7%,$(target_part)),)
vhdl-sources := $(filter-out pll_basic_simulation.vhd,$(vhdl-sources))

vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_config_series67.vhd
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pll_config_series6.vhd
deps += nsl_hwconfig.xc6_config
else ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += pll_config_series7.vhd
deps += nsl_hwconfig.xc7_config
endif

vhdl-sources += pll_backend_series67.vhd
vhdl-sources += pll_multi_series67.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_math.arith
deps += nsl_data.text
endif

ifneq ($(filter lattice-ecp5,$(hwdep)),)
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_ecp5.vhd
vhdl-sources += pll_multi_ecp5.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_data.text
endif

ifneq ($(filter altera,$(hwdep)),)
ifneq ($(filter 10CL%,$(target_part)),)
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_cyclone10lp.vhd
vhdl-sources += pll_multi_cyclone10lp.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_data.text
deps += nsl_hwconfig.cyclone10lp_config
endif
ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += pll_backend.pkg.vhd
vhdl-sources += pll_backend_agilex5.vhd
vhdl-sources += pll_multi_agilex5.vhd
vhdl-sources += pll_basic.vhd
deps += nsl_data.text
deps += nsl_hwconfig.agilex5_config
endif
endif
