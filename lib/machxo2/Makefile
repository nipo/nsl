ifeq ($(wildcard $(srcdir)/.prepared)$(internal),)
$(warning Your design seems to depend on machxo2, but sources are not copied in yet.)
$(warning Before building with non-Lattice tools, you should run)
$(warning `make -f prepare.mk copy` in lib/machxo2 directory)
else
vhdl-sources += MACHXO2COMP.vhd
vhdl-sources += MACHXO2_CMB.vhd
vhdl-sources += MACHXO2_CNT.vhd
vhdl-sources += MACHXO2_IO.vhd
vhdl-sources += MACHXO2_LUT.vhd
vhdl-sources += MACHXO2_MEM.vhd
vhdl-sources += MACHXO2_MISC.vhd
vhdl-sources += MACHXO2_SEQ.vhd
vhdl-sources += gsr_pur_assign.vhd
endif
