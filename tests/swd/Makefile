CONFIG_NSL_SWD = y
CONFIG_NSL_FIFO = y
CONFIG_NSL_TESTING = y

libraries = nsl testing work
nsl-srcdir = ../../lib/nsl
testing-srcdir = ../../lib/testing
work-srcdir = src

tool = ghdl
top = tb

include ../../build/build.mk

tb.ghw: swd_responses.txt swd_commands.txt

swd_responses.txt swd_commands.txt: txn_gen
	./$< $@
