vhdl-sources += clock.pkg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += clock_internal_spartan6.vhd
deps += unisim.vcomponents
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += clock_internal_7series.vhd
deps += unisim.vcomponents
endif
endif

ifeq ($(tool),isim)
vhdl-sources += clock.pkg_body-isim.vhd
else
vhdl-sources += clock.pkg_body-generic.vhd
endif

ifneq ($(filter lattice-machxo2,$(hwdep)),)
vhdl-sources += clock_internal_mxo2.vhd
deps += machxo2.components
endif

deps += hwdep.io
