vhdl-sources += delay.pkg.vhd
vhdl-sources += input_bus_delay_fixed.vhd
vhdl-sources += output_bus_delay_fixed.vhd

ifeq ($(hwdep),simulation)
vhdl-sources += input_delay_fixed_simulation.vhd
vhdl-sources += output_delay_fixed_simulation.vhd
endif

ifeq ($(hwdep),xilinx)
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += input_delay_fixed_xc6.vhd
vhdl-sources += output_delay_fixed_xc6.vhd
deps += nsl_hwdep.xc6_config
else
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += input_delay_fixed_xc7.vhd
vhdl-sources += output_delay_fixed_xc7.vhd
endif
endif
deps += unisim.vcomponents
deps += nsl_data.text
endif

ifeq ($(hwdep),gowin)
vhdl-sources += input_delay_fixed_gowin.vhd
vhdl-sources += output_delay_fixed_gowin.vhd
deps += gowin.components
endif
