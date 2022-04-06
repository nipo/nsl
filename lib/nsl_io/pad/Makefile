vhdl-sources += pad.pkg.vhd

ifeq ($(hwdep),xilinx)
vhdl-sources += pad_diff_output_xc.vhd
vhdl-sources += pad_tmds_output_xc.vhd
vhdl-sources += pad_tmds_input_xc.vhd

ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += pad_diff_input_xc6.vhd
vhdl-sources += pad_diff_clock_input_xc6.vhd
endif

ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += pad_diff_input_xc7.vhd
vhdl-sources += pad_diff_clock_input_xc7.vhd
endif

deps += unisim.vcomponents
endif

ifeq ($(hwdep),simulation)
vhdl-sources += pad_diff_output_simulation.vhd
vhdl-sources += pad_tmds_output_simulation.vhd
vhdl-sources += pad_tmds_input_simulation.vhd
vhdl-sources += pad_diff_input_simulation.vhd
vhdl-sources += pad_diff_clock_input_simulation.vhd
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += pad_diff_input_gowin.vhd
vhdl-sources += pad_diff_output_gowin.vhd
deps += gowin.components
endif

deps += nsl_io.diff
