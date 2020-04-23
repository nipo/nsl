vhdl-sources += reset.pkg.vhd

ifneq ($(filter $(tool),isim vivado ise),)
vhdl-sources += reset_at_startup_xc.vhd
deps += unisim
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += reset_at_startup_mxo2.vhd
deps += machxo2.components
endif

ifeq ($(tool),ghdl)
vhdl-sources += reset_at_startup_sim.vhd
endif
