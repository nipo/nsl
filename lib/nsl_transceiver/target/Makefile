vhdl-sources += target.pkg.vhd

ifeq ($(hwdep),gowin)
ifneq ($(filter GW5%,$(target_part)),)
vhdl-sources += target_gw5a.vhd
endif
endif

ifeq ($(hwdep),xilinx)
vhdl-sources += target_gtpe2.vhd
endif
