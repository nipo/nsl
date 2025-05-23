vhdl-sources += control.pkg.vhd

ifeq ($(GHDL_LLVM),)
control-ghdl := control_ghdl.vhd
else
control-ghdl := control_vhpidirect.vhd
endif
control-xsim := control_xsim.vhd
control-nvc := control_nvc.vhd

nvc-plugin += control_nvc_backend
control_nvc_backend-plugin-sources := $(srcdir)/control_nvc_backend.c

control-generic := control_generic.vhd
control-questa := control_finish.vhd

vhdl-sources += $(if $(control-$(tool)),$(control-$(tool)),$(control-generic))
