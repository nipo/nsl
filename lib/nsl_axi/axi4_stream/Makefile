vhdl-sources += axi4_stream.pkg.vhd
vhdl-sources += axi4_stream_fifo.vhd

deps += nsl_math.arith
deps += nsl_logic.bool
deps += nsl_data.bytestream
deps += nsl_data.endian
deps += nsl_data.text
deps += nsl_memory.fifo

ifeq (simulation,$(target-usage))
vhdl-sources += axi4_stream_dumper.vhd
deps += nsl_simulation.logging
else
vhdl-sources += axi4_stream_dumper_null.vhd
endif
