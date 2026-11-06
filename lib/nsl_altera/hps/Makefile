vhdl-sources += hps.pkg.vhd
vhdl-sources += hps_boundary_register.vhd
vhdl-sources += hps_bridge_channel.vhd
vhdl-sources += hps_master_bridge.vhd
vhdl-sources += hps_slave_bridge.vhd

ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += hps_wrapper.vhd
endif

deps += nsl_amba.axi4_mm
deps += nsl_memory.fifo
deps += nsl_clocking.async
deps += nsl_data.endian
