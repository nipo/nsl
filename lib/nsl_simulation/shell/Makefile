vhdl-sources += shell.pkg.vhd

ifneq ($(filter ghdl yavs,$(tool)),)

vhdl-sources += shell-vhpidirect.vhd
vhpidirect-sources += shell-vhpidirect.c

else

vhdl-sources += shell-none.vhd

endif

deps += nsl_data.bytestream
