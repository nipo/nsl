TESTS := analyzer cc ddr_io easyscale fifo fifo2 fifo3 	\
fifo_delay flit ftdi gray i2c ioext mii rmii spi_bridge swd uart_8n1

all:

clean:

FORCE:
	@

define subtest

$1/test: $1/Makefile
	make -C $1

$1/clean: FORCE
	make -C $1 clean

$1/Makefile:

all: $1/test

clean: $1/clean

endef

$(eval $(foreach t,$(TESTS),$(call subtest,$t)))
