ip += activity_monitor
ip += axis_ws2812
ip += axis_ws2812_column_driver
ip += i2c_input_deglitcher

all:

define ip_declare

.PHONY: $1/do_package $1/do_synth FORCE
FORCE:

$1/do_package: $1/Makefile FORCE
	make -C $1

$1/do_synth: $1/Makefile FORCE
	make -C $1 synth

all: $1/do_package

synth: $1/do_synth

endef

$(eval $(foreach i,$(ip),$(call ip_declare,$(i))))
