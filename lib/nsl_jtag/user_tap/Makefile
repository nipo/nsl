vhdl-sources += user_tap.pkg.vhd
vhdl-sources += jtag_reg.vhd

ifneq ($(filter xc%,$(target_part)),)
ifneq ($(filter xc6slx%,$(target_part)),)
vhdl-sources += jtag_tap_register_spartan6.vhd
vhdl-sources += jtag_user_tap_spartan6.vhd
endif
ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += jtag_tap_register_7series.vhd
vhdl-sources += jtag_user_tap_series7.vhd
endif
endif

ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += jtag_user_tap_gowin.vhd
deps += nsl_clocking.distribution
endif

ifneq ($(filter simulation,$(hwdep)),)
vhdl-sources += jtag_user_register_simulation.vhd
vhdl-sources += jtag_user_tap_simulation.vhd
deps += nsl_simulation.jtag
endif

ifneq ($(filter lattice-ecp5,$(hwdep)),)
vhdl-sources += jtag_user_tap_ecp5.vhd
deps += nsl_clocking.distribution
deps += sb_ice.components
endif

ifneq ($(filter altera,$(hwdep)),)
ifneq ($(filter 10CL%,$(target_part)),)
vhdl-sources += jtag_user_tap_cyclone10lp.vhd
deps += nsl_clocking.distribution
deps += nsl_jtag.tap
endif
ifneq ($(filter A5E%,$(target_part)),)
vhdl-sources += jtag_user_tap_altera_vjtag.vhd
endif
endif
