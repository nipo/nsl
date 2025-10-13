vhdl-sources += tcp_socket.pkg.vhd
deps += nsl_simulation.socket

ifeq ($(tool),ghdl)

vhdl-sources += tcp_socket-vhpidirect.vhd
vhpidirect-plugin += tcp_socket
tcp_socket-plugin-sources := $(srcdir)/tcp_socket-vhpidirect.c

else

vhdl-sources += tcp_socket-none.vhd

endif

deps += nsl_data.bytestream
