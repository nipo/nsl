vhdl-sources += ram.pkg.vhd
vhdl-sources += ram_1p.vhd
vhdl-sources += ram_1p_multi.vhd
ifneq ($(filter gowin,$(hwdep)),)
vhdl-sources += ram_2p_homogeneous_gowin.vhd
else
vhdl-sources += ram_2p_homogeneous.vhd
endif
vhdl-sources += ram_2p_r_w.vhd
vhdl-sources += ram_2p.vhd
deps += nsl_math.arith
