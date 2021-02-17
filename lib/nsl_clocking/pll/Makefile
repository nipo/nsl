vhdl-sources += pll.pkg.vhd

ifeq ($(tool),ghdl)
vhdl-sources += pll_basic_simulation.vhd
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += pll_basic_ice40.vhd
deps += nsl_data.text
deps += sb_ice
endif

ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += pll_basic_spartan6.vhd
deps += unisim.vcomponents
deps += nsl_math.arith
deps += nsl_data.text
deps += nsl_logic.bool
endif
