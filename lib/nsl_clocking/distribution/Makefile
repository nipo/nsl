vhdl-sources += distribution.pkg.vhd

ifeq ($(hwdep),simulation)
vhdl-sources += clock_buffer_simulation.vhd
endif

ifeq ($(hwdep),xilinx)
vhdl-sources += clock_buffer_xilinx.vhd
endif

ifeq ($(hwdep),lattice-machxo2)
vhdl-sources += clock_buffer_machxo2.vhd
deps += machxo2.components
endif

ifeq ($(hwdep),lattice-ice40)
vhdl-sources += clock_buffer_ice40.vhd
deps += sb_ice.components
endif

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5A%,$(target_part_name)),)
vhdl-sources += clock_buffer_gowin_5a.vhd
else
vhdl-sources += clock_buffer_gowin.vhd
endif
deps += gowin.components
endif

ifneq ($(filter lattice-ecp5,$(hwdep)),)
ifeq ($(compiler),yosys)
vhdl-sources += clock_buffer_ecp5_yosys.vhd
else
vhdl-sources += clock_buffer_ecp5.vhd
endif
deps += sb_ice.components
endif
