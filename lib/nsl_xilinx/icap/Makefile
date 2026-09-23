vhdl-sources += icap.pkg.vhd

ifneq ($(filter xc7%,$(target_part)),)
vhdl-sources += config_series7.vhd
deps += nsl_data.endian
endif
