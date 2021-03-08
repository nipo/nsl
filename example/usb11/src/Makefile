vhdl-sources += main.vhd
ifeq ($(hwdep),lattice-ice40)
constraint-sources += main.pcf
constraint-sources += main.sdc
endif
ifeq ($(hwdep),lattice-machxo2)
constraint-sources += main.lpf
endif

deps += nsl_hwdep.clock
deps += nsl_hwdep.uid
deps += nsl_hwdep.reset
deps += nsl_clocking.async
deps += nsl_memory.fifo
deps += nsl_usb.usb
deps += nsl_usb.utmi
deps += nsl_usb.fs_phy
deps += nsl_usb.func
deps += nsl_usb.io
deps += nsl_hwdep.ice40
deps += nsl_ftdi.ft245
deps += nsl_clocking.pll
deps += nsl_bnoc.framed
deps += nsl_spi.transactor
