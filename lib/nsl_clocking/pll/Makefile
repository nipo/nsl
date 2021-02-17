vhdl-sources += pll.pkg.vhd

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += pll_basic_ice40.vhd
deps += nsl_simulation.text
deps += sb_ice
endif
