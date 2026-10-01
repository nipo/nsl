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

ifneq ($(filter zynqusp%,$(family)),)
vhdl-sources += transceiver_cluster_gthe4.vhd
vhdl-sources += transceiver_config_gthe4.vhd
deps += nsl_data.bytestream
deps += nsl_logic.gearbox
deps += nsl_clocking.distribution
deps += nsl_clocking.async
deps += nsl_synthesis.assertion
endif

ifneq ($(filter artix7%,$(family)),)
vhdl-sources += transceiver_cluster_gtpe2.vhd
vhdl-sources += transceiver_config_gtpe2.vhd
deps += nsl_data.bytestream
deps += nsl_hwconfig.xc7_config
deps += nsl_logic.gearbox
deps += nsl_clocking.distribution
deps += nsl_clocking.async
deps += nsl_synthesis.assertion
endif

endif
