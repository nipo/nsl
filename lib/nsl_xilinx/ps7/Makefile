vhdl-sources += ps7.pkg.vhd
vhdl-sources += ps7_axi3_wid_tracker.vhd

ifneq ($(filter xc7z%,$(target_part)),)
vhdl-sources += ps7_wrapper.vhd
endif

deps += nsl_amba.axi4_mm
deps += nsl_amba.dma_request
deps += nsl_data.endian
deps += nsl_spi.spi
deps += nsl_mii.gmii
deps += nsl_smi.smi
deps += nsl_uart.uart
deps += nsl_i2c.i2c
deps += nsl_io.io
