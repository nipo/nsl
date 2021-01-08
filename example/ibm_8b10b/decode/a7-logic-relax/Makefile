target = logic
top = src.top
src-srcdir = $(SRC_DIR)/../src
target_part = xc7a75t
target_package = ftg256
target_speed = -2
hwdep = xilinx
tool = vivado
topcell-generics=$(call generic-string,implementation_c,$(target)) $(call generic-bool,strict_c,false)

all: $(target)-compressed.bit

include ../../../../build/build.mk
