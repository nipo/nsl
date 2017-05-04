CONFIG_NSL_NOC=y
CONFIG_NSL_TESTING=y

libraries = nsl testing work
nsl-srcdir = ../../lib/nsl
testing-srcdir = ../../lib/testing
work-srcdir = src

tool = ghdl
top = tb

include ../../build/build.mk

tb.ghw: ez_cmd.txt ez_rsp.txt

ez_cmd.txt ez_rsp.txt: txn_gen
	./txn_gen $@
