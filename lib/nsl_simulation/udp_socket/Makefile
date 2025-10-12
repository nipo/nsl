vhdl-sources += udp_socket.pkg.vhd
deps += nsl_simulation.socket

ifeq ($(tool),ghdl)

vhdl-sources += udp_socket-vhpidirect.vhd
vhpidirect-plugin += udp_socket
udp_socket-plugin-sources += $(srcdir)/udp_socket-vhpidirect.c

else

vhdl-sources += udp_socket-none.vhd

endif

deps += nsl_data.bytestream
