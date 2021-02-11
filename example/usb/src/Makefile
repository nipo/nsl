vhdl-sources += main.vhd
ifeq ($(tool),icecube2)
constraint-sources += main.pcf
constraint-sources += main.sdc
endif
ifeq ($(tool),ise)
constraint-sources += main.ucf
endif
deps += nsl_hwdep.clock
deps += nsl_hwdep.uid
deps += nsl_hwdep.reset
deps += nsl_clocking.async
deps += nsl_memory.fifo
deps += nsl_usb.usb
deps += nsl_usb.utmi
deps += nsl_usb.ulpi
deps += nsl_usb.func
deps += nsl_hwdep.ice40
deps += nsl_ftdi.ft245
