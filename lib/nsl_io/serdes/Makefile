vhdl-sources += serdes.pkg.vhd

deps += nsl_data.text

ifeq ($(hwdep),xilinx)
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += serdes_ddr10_output_series7.vhd
vhdl-sources += serdes_ddr10_input_series7.vhd
vhdl-sources += serdes_output_series7.vhd
vhdl-sources += serdes_input_series7.vhd
endif
# Note for Series-6: There is an embryo, but Series-6
# serdeses need IOCE signal driven from global buffers
# to create a strobe on parallel bus with a length of
# one serial cycle. This does not fit the API right now.
ifneq ($(filter xc6%,$(target_part)),)
vhdl-sources += serdes_sdr10_output_series6.vhd
vhdl-sources += serdes_sdr10_input_series6.vhd
# vhdl-sources += serdes_output_series6.vhd
# vhdl-sources += serdes_input_series6.vhd
endif
deps += unisim.vcomponents
endif

ifeq ($(hwdep),gowin)
vhdl-sources += serdes_ddr10_output_gowin.vhd
vhdl-sources += serdes_ddr10_input_gowin.vhd
vhdl-sources += serdes_output_gowin.vhd
vhdl-sources += serdes_input_gowin.vhd
vhdl-sources += serdes_blocks_gowin.vhd
endif

ifeq ($(hwdep),simulation)
vhdl-sources += serdes_ddr10_output_simulation.vhd
vhdl-sources += serdes_ddr10_input_simulation.vhd
vhdl-sources += serdes_sdr10_output_simulation.vhd
vhdl-sources += serdes_sdr10_input_simulation.vhd
vhdl-sources += serdes_output_simulation.vhd
vhdl-sources += serdes_input_simulation.vhd
endif
