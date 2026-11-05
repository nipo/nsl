vhdl-sources += ps8.pkg.vhd

ifneq ($(filter xczu% xck%,$(target_part)),)
vhdl-sources += ps8_wrapper.vhd
endif

deps += nsl_amba.axi4_mm
deps += nsl_data.endian
deps += nsl_spi.spi
deps += nsl_mii.gmii
deps += nsl_smi.smi
deps += nsl_uart.uart
deps += nsl_i2c.i2c
deps += nsl_io.io
