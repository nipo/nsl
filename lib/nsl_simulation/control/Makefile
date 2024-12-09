vhdl-sources += control.pkg.vhd
ifeq ($(tool)$(GHDL_LLVM),ghdl)
vhdl-sources += control_ghdl.vhd
else
ifeq ($(tool),ghdl)
vhdl-sources += control_vhpidirect.vhd
else
vhdl-sources += control_generic.vhd
endif
endif
