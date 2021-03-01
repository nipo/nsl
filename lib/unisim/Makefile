ifeq ($(wildcard $(srcdir)/.prepared)$(internal),)
$(warning Your design seems to depend on unisim, but sources are not copied in yet.)
$(warning Before building with non-Xilinx tools, you should run)
$(warning `make -f prepare.mk copy` in lib/unisim directory)
endif

packages += vpkg
packages += vcomponents
unisim-ghdl-flags = -fsynopsys -frelaxed-rules -fexplicit
