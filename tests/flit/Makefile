top = work.tb
work-srcdir = $(SRC_DIR)/src
tool = ghdl

include ../../build/build.mk

tb.ghw: framed.txt flit.txt

framed.txt flit.txt: _generate

_generate: gen.py
	./gen.py framed.txt flit.txt

