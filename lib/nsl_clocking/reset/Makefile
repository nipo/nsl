vhdl-sources += reset.pkg.vhd

ifneq ($(filter lattice-ice40,$(hwdep)),)
vhdl-sources += reset_at_startup_ice40.vhd
else
ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += reset_at_startup_mxo2.vhd
deps += machxo2.components
else
vhdl-sources += reset_at_startup_generic.vhd
endif
endif
