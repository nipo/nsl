vhdl-sources += blink.vhd
ifeq ($(hwdep),xilinx)
constraint-sources += led.ucf
else
constraint-sources += led.pcf
endif
deps += nsl_hwdep.clock

