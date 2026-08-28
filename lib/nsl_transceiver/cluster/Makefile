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
vhdl-sources += transceiver_cluster_gtpe2.vhd
vhdl-sources += transceiver_config_gtpe2.vhd
deps += nsl_data.bytestream
deps += nsl_hwdep.xc7_config
deps += nsl_logic.gearbox
deps += nsl_clocking.distribution
deps += nsl_clocking.async
endif
