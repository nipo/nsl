vhdl-sources += axi4_stream.pkg.vhd
vhdl-sources += axi4_stream_flusher.vhd
vhdl-sources += axi4_stream_width_adapter.vhd
vhdl-sources += axi4_stream_header_extractor.vhd
vhdl-sources += axi4_stream_header_inserter.vhd
vhdl-sources += axi4_stream_protocol_assertions.vhd

deps += nsl_math.arith
deps += nsl_logic.bool
deps += nsl_logic.logic
deps += nsl_data.bytestream
deps += nsl_data.endian
deps += nsl_data.text

ifeq (simulation,$(target-usage))
vhdl-sources += axi4_stream_dumper.vhd
deps += nsl_simulation.logging
else
vhdl-sources += axi4_stream_dumper_null.vhd
endif
