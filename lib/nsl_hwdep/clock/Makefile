vhdl-sources += clock.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += clock_buffer_xilinx.vhd
deps += unisim.vcomponents
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += clock_internal_7series.vhd
endif
else
ifeq ($(tool),ghdl)
vhdl-sources += clock_internal_sim.vhd
endif
endif

ifeq ($(tool),efinity)
vhdl-sources += clock_internal_efinix.vhd
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += clock_internal_mxo2.vhd
vhdl-sources += clock_buffer_machxo2.vhd
deps += machxo2.components
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += clock_internal_gowin.vhd
deps += nsl_hwdep.gowin_config
deps += gowin.components
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += clock_internal_ice40.vhd
vhdl-sources += clock_buffer_ice40.vhd
deps += sb_ice
endif
