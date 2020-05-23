vhdl-sources += blink.vhd
ifeq ($(hwdep),xilinx)
constraint-sources += led.ucf
else
ifeq ($(hwdep),lattice-machxo2)
constraint-sources += led.lpf
else
constraint-sources += led.pcf
endif
endif
deps += nsl_hwdep.clock

