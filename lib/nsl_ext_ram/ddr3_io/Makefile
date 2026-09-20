vhdl-sources += ddr3_io.pkg.vhd
ifeq ($(hwdep),gowin)
vhdl-sources += ddr3_phy_gowin.vhd
endif

vhdl-sources += ddr3_phy_simulation.vhd
vhdl-sources += ddr3_phy_serdes.vhd
deps += nsl_ext_ram.timing
deps += nsl_ext_ram.dfi
deps += nsl_data.bytestream
deps += nsl_io.io
deps += nsl_io.diff
deps += nsl_io.serdes
deps += nsl_io.delay
deps += nsl_logic.bool
