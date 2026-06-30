vhdl-sources += group.pkg.vhd

deps += nsl_transceiver.lane
deps += nsl_io.diff
deps += nsl_amba.apb

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += transceiver_group_gw5a.vhd
vhdl-sources += apb_upar_bridge_gw5a.vhd
deps += gowin.components
deps += nsl_data.endian
endif
endif
