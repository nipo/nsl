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

vhdl-sources += transceiver_utils.pkg.vhd
vhdl-sources += lane_aligner.vhd
vhdl-sources += lane_gearbox.vhd
deps += nsl_data.bytestream
deps += nsl_logic.gearbox
deps += nsl_clocking.distribution
deps += nsl_clocking.async
deps += nsl_synthesis.assertion

ifneq ($(filter zynqusp%,$(family)),)
vhdl-sources += transceiver_cluster_gthe4.vhd
vhdl-sources += transceiver_config_gthe4.vhd
vhdl-sources += gthe4_cpll_reset_fsm.vhd
vhdl-sources += gthe4_reset_fsm.vhd
endif

ifneq ($(filter artix7%,$(family)),)
vhdl-sources += transceiver_cluster_gtpe2.vhd
vhdl-sources += transceiver_config_gtpe2.vhd
vhdl-sources += gtpe2_pll_reset_fsm.vhd
vhdl-sources += gtpe2_reset_fsm.vhd
deps += nsl_clocking.pll
endif

endif
