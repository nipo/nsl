vhdl-sources += axi4_mm.pkg.vhd
vhdl-sources += axi4_mm_ram.vhd

deps += nsl_logic.bool
deps += nsl_logic.logic
deps += nsl_data.bytestream
deps += nsl_data.endian
deps += nsl_data.text
deps += nsl_math.arith
deps += nsl_memory.ram

ifeq (simulation,$(target-usage))
vhdl-sources += axi4_mm_dumper.vhd
deps += nsl_simulation.logging
else
vhdl-sources += axi4_mm_dumper_null.vhd
endif
