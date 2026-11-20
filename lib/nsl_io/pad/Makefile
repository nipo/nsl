vhdl-sources += pad.pkg.vhd
vhdl-sources += pad_sstl_generic.vhd

ifeq ($(hwdep),xilinx)
vhdl-sources += pad_diff_output_xc.vhd
vhdl-sources += pad_diff_output_tristated_xc.vhd
vhdl-sources += pad_diff_io_xc.vhd
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

# UltraScale / UltraScale+ (Kintex, Virtex, Zynq MPSoC, Artix US+, Kria)
# One pattern per filter: the gbs nsl-tree loader does not split
# space-separated filter patterns the way GNU make does.
ifneq ($(filter xcku%,$(target_part))$(filter xcvu%,$(target_part))$(filter xczu%,$(target_part))$(filter xcau%,$(target_part))$(filter xck2%,$(target_part)),)
vhdl-sources += pad_diff_input_xcu.vhd
endif
endif

ifeq ($(hwdep),simulation)
vhdl-sources += pad_diff_output_simulation.vhd
vhdl-sources += pad_diff_output_tristated_simulation.vhd
vhdl-sources += pad_diff_io_simulation.vhd
vhdl-sources += pad_tmds_output_simulation.vhd
vhdl-sources += pad_tmds_input_simulation.vhd
vhdl-sources += pad_diff_input_simulation.vhd
vhdl-sources += pad_diff_clock_input_simulation.vhd
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += pad_diff_input_gowin.vhd
vhdl-sources += pad_diff_output_gowin.vhd
vhdl-sources += pad_tmds_output_gowin.vhd
endif

deps += nsl_io.diff
deps += nsl_io.io
