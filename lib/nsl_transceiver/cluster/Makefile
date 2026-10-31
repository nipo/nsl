vhdl-sources += cluster.pkg.vhd

deps += nsl_transceiver.lane
deps += nsl_transceiver.target
deps += nsl_io.diff
deps += nsl_amba.apb
deps += nsl_math.int_ext

# Vendor-independent building blocks. None of these reaches a vendor
# primitive: the aligner and the gearbox are plain logic, the reset
# sequencers express a vendor's documented reset order as a state
# machine, and the configuration packages are its divider tables and
# field encodings. They are compiled on every target, simulation
# included, so a testbench can exercise them without the primitive
# they end up driving.
vhdl-sources += transceiver_utils.pkg.vhd
vhdl-sources += lane_aligner.vhd
vhdl-sources += lane_gearbox.vhd
vhdl-sources += transceiver_config_gtpe2.vhd
vhdl-sources += gtpe2_pll_reset_fsm.vhd
vhdl-sources += gtpe2_reset_fsm.vhd
vhdl-sources += transceiver_config_gthe4.vhd
vhdl-sources += gthe4_cpll_reset_fsm.vhd
vhdl-sources += gthe4_reset_fsm.vhd
deps += nsl_logic.gearbox

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += transceiver_cluster_gw5a.vhd
vhdl-sources += apb_upar_bridge_gw5a.vhd
deps += gowin.components
deps += nsl_data.endian
endif
endif

ifeq ($(hwdep),xilinx)

deps += nsl_data.bytestream
deps += nsl_clocking.distribution
deps += nsl_clocking.async
deps += nsl_synthesis.assertion

# The two cluster files below reach their channel primitive through
# "library unisim", which Vivado resolves on its own. Every other
# Xilinx primitive in NSL is declared locally with a BOX_TYPE
# attribute instead, so no lib/unisim preparation is needed; these
# two files are the exception and still have to be converted. Until
# they are, they cannot be analysed outside Vivado, which is why
# everything testable has been kept out of them.

ifneq ($(filter zynqusp%,$(family)),)
vhdl-sources += transceiver_cluster_gthe4.vhd
endif

ifneq ($(filter artix7%,$(family)),)
vhdl-sources += transceiver_cluster_gtpe2.vhd
deps += nsl_clocking.pll
endif

endif
