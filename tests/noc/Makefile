CONFIG_NSL_NOC=y
CONFIG_NSL_TESTING=y

libraries = nsl testing work
nsl-srcdir = ../../lib/nsl
testing-srcdir = ../../lib/testing
work-srcdir = src

tool = ghdl
top = tb

include ../../build/build.mk

tb.ghw: input_0.txt output_0.txt output_1.txt

input_0.txt: flit_gen
	./flit_gen src 0 0 1 > $@

output_0.txt: flit_gen
	./flit_gen dst 0 0 > $@

output_1.txt: flit_gen
	./flit_gen dst 1 0 > $@
