ifeq ($(wildcard $(srcdir)/.prepared)$(internal),)
$(warning Your design seems to depend on sb_ice, but sources are not copied in yet.)
$(warning Before building with non-Lattice tools, you should run)
$(warning `make -f prepare.mk copy` in lib/sb_ice directory)
else
vhdl-sources += sb_ice40_components_syn.vhd
endif
