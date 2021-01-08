target = spec
top = src.top
src-srcdir = $(SRC_DIR)/../src
target_part = xc6slx9
target_package = tqg144
target_speed = -2
hwdep = xilinx
tool = ise
topcell-generics=$(call generic-string,implementation_c,$(target))

all: $(target)-compressed.bit

include ../../../../build/build.mk
