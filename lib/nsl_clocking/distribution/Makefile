vhdl-sources += distribution.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += clock_buffer_xilinx.vhd
deps += unisim.vcomponents
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += clock_buffer_machxo2.vhd
deps += machxo2.components
endif

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += clock_buffer_ice40.vhd
deps += sb_ice
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += clock_buffer_gowin.vhd
endif
