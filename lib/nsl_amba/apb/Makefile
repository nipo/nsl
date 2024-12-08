vhdl-sources += apb.pkg.vhd
vhdl-sources += apb_slave.vhd
vhdl-sources += apb_regmap.vhd

ifeq (simulation,$(target-usage))
vhdl-sources += apb_dumper.vhd
deps += nsl_simulation.logging
else
vhdl-sources += apb_dumper_null.vhd
endif

deps += nsl_math.arith
deps += nsl_amba.address
deps += nsl_logic.bool
deps += nsl_logic.logic
deps += nsl_data.bytestream
deps += nsl_data.endian
deps += nsl_data.text
