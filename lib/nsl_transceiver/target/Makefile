vhdl-sources += target.pkg.vhd

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += target_gw5a.vhd
endif
endif

ifeq ($(hwdep),xilinx)

ifneq ($(filter artix7%,$(family)),)
vhdl-sources += target_gtpe2.vhd
endif

ifneq ($(filter zynqusp%,$(family)),)
vhdl-sources += target_gthe4.vhd
endif

endif
