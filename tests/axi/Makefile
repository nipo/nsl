tb += axi4_mm_lite_ram
tb += axi4_mm_lite_regmap
tb += axi4_mm_lite_stream_endpoint
tb += axi4_mm_ram
tb += axi4_mm_types
tb += axi4_stream_types
tb += axi4_stream_fifo
tb += axi4_stream_flusher
tb += axi4_stream_narrower
tb += axi4_stream_widener
tb += axi4_mm_on_stream

all: simulate

define tb_declare

.PHONY: $1/simulate FORCE
FORCE:

$1/simulate: $1/Makefile FORCE
	make -C $1 simulate

simulate: $1/simulate

endef

$(eval $(foreach i,$(tb),$(call tb_declare,$(i))))
