vhdl-sources += avalon_st.pkg.vhd
vhdl-sources += avalon_st_ready_latency_adapter.vhd
vhdl-sources += avalon_st_width_adapter.vhd

deps += nsl_math.arith
deps += nsl_logic.bool
deps += nsl_data.bytestream
deps += nsl_data.endian
deps += nsl_data.text

ifeq (simulation,$(target-usage))
vhdl-sources += avalon_st_dumper.vhd
deps += nsl_simulation.logging
else
vhdl-sources += avalon_st_dumper_null.vhd
endif
