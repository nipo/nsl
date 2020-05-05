ip += activity_monitor
ip += axis_ws2812
ip += axis_ws2812_column_driver
ip += framed_spi_controller
ip += framed_i2c_controller
ip += framed_swd_controller
ip += framed_jtag_controller
ip += i2c_input_deglitcher
ip += routed_endpoint
ip += routed_router
ip += axi4lite_ram
ip += swd_axi4lite_master

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
