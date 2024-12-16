vhdl-sources += control.pkg.vhd

ifeq ($(GHDL_LLVM),)
control-ghdl := control_ghdl.vhd
else
control-ghdl := control_vhpidirect.vhd
endif
control-xsim := control_xsim.vhd
control-generic := control_generic.vhd
control-questa := control_finish.vhd

vhdl-sources += $(if $(control-$(tool)),$(control-$(tool)),$(control-generic))
