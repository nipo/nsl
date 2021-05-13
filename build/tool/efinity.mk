EFINITY=/opt/efinix/efinity/2020.1
MAP=$(EFINITY)/bin/efx_map
PNR=$(EFINITY)/bin/efx_pnr
PGM=$(EFINITY)/bin/efx_pgm

elang-vhdl-=vhdl_93
elang-vhdl-93=vhdl_93
elang-vhdl-2008=vhdl_2008

elang=$(elang-$($(1)-language)-$($($(1)-package)-vhdl-version))

$(target).vdb: $(sources) $(MAKEFILE_LIST)
	mkdir -p $(build-dir)
	mkdir -p $(build-dir)/map
	$(MAP) --project $(target) --root $(top-entity) \
		--binary-db $@ \
		--device $(target_part) \
		--family $(target_family) \
		--syn_options mode=speed \
		--veri_option verilog_mode=verilog_2k,vhdl_mode=vhdl_93 \
		--work-dir $(build-dir)/ \
		--output-dir $(build-dir)/map/ \
		$(foreach s,$(sources), --v $s,t:$(call elang,$s),l:$($s-library))

$(target).route: $(target).vdb
	mkdir -p $(build-dir)
	mkdir -p $(build-dir)/pnr
	$(PNR) --circuit $(target) \
		--family $(target_family) \
		--device $(target_part) \
		--operating_conditions $(target_oc) \
		--pack --place --route \
		--vdb_file $< --use_vdb_file on \
		--place_file $(@:.route=.place) \
		--route_file $@ \
		--sync_file $@.sync.csv \
		--work_dir $(build-dir)/ \
		--output_dir $(build-dir)/pnr/ \
		--timing_analysis on --load_delay_matrix

$(target).hex: $(target).lbf
	$(PGM) \
		--source $< \
		--dest $@ \
		--family $(target_family) \
		--device $(target_part) \
		--periph $(target).lpf \
		--oscillator_clock_divider DIV8 \
		--spi_low_power_mode on \
		--io_weak_pullup on \
		--enable_roms on \
		--mode active --width 1 \
		--enable_crc_check on
