vhdl-sources += shell.pkg.vhd

ifeq ($(tool),ghdl)

vhdl-sources += shell-vhpidirect.vhd
vhpidirect-sources += shell-vhpidirect.c

else

vhdl-sources += shell-none.vhd

endif

deps += nsl_data.bytestream
