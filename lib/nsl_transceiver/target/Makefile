vhdl-sources += target.pkg.vhd

# The simulation body recognises every name the real targets do, so
# a design written for any of them simulates unchanged.
ifeq ($(hwdep),simulation)
vhdl-sources += target_simulation.vhd
endif

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += target_gw5a.vhd
endif
endif

ifeq ($(hwdep),xilinx)

ifneq ($(filter artix7%,$(family)),)
vhdl-sources += target_gtpe2.vhd
endif

# Series 7 families without a transceiver cluster: only the bulk IO
# backend, and its single reference clock.
ifneq ($(filter kintex7% virtex7% zynq7% spartan7%,$(family)),)
vhdl-sources += target_series7_serdes.vhd
endif

ifneq ($(filter zynqusp%,$(family)),)
vhdl-sources += target_gthe4.vhd
endif

endif
