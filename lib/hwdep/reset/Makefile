vhdl-sources += reset.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
vhdl-sources += reset_at_startup_xc.vhd
deps += unisim.vcomponents
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += reset_at_startup_mxo2.vhd
deps += machxo2.components
endif
