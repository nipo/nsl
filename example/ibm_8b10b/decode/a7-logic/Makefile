target = logic
top = src.top
src-srcdir = $(SRC_DIR)/../src
target_part = xc7a15t
target_package = ftp256
target_speed = -2
hwdep = xilinx
tool = vivado
topcell-generics=$(call generic-string,implementation_c,$(target))

all: $(target)-compressed.bit

include ../../../../build/build.mk
