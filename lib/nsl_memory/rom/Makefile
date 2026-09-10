vhdl-sources += rom.pkg.vhd
vhdl-sources += rom_bytes.vhd
ifeq ($(compiler),yosys)
vhdl-sources += rom_bytes_2p_yosys.vhd
else
vhdl-sources += rom_bytes_2p.vhd
endif
deps += nsl_data.endian
deps += nsl_data.bytestream
