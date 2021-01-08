vhdl-sources += clock.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += clock_buffer_xilinx.vhd
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
deps += unisim.vcomponents
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += clock_internal_7series.vhd
deps += unisim.vcomponents
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
deps += machxo2.components
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += clock_internal_ice40.vhd
deps += sb_ice
endif
