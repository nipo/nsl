libraries = nsl testing work
testing-srcdir = ../../lib/testing
nsl-srcdir = ../../lib/nsl
work-srcdir = src

tool = ghdl
top = tb

include ../../build/build.mk

tb.ghw: framed.txt flit.txt

framed.txt flit.txt: _generate

_generate: gen.py
	./gen.py framed.txt flit.txt

