vhdl-sources += cluster.pkg.vhd

deps += nsl_transceiver.lane
deps += nsl_transceiver.target
deps += nsl_io.diff
deps += nsl_amba.apb
deps += nsl_math.int_ext

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += transceiver_cluster_gw5a.vhd
vhdl-sources += apb_upar_bridge_gw5a.vhd
deps += gowin.components
deps += nsl_data.endian
endif
endif

ifeq ($(hwdep),xilinx)
vhdl-sources += transceiver_cluster_series7_serdes.vhd
deps += nsl_data.bytestream
deps += nsl_hwconfig.xc7_config
deps += nsl_clocking.pll
deps += nsl_io.pad
deps += nsl_io.serdes
deps += nsl_io.delay
deps += nsl_line_coding.ibm_8b10b
deps += nsl_logic.gearbox
deps += nsl_clocking.distribution
deps += nsl_clocking.async
deps += nsl_synthesis.assertion
endif
