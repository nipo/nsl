ifeq ($(wildcard $(srcdir)/.prepared)$(internal),)
$(warning Your design seems to depend on simprim, but sources are not copied in yet.)
$(warning Before building with non-Xilinx tools, you should run)
$(warning `make -f prepare.mk copy` in lib/simprim directory)
endif

packages += vcomponents
packages += vpackage

simprim-ghdl-flags = -fsynopsys -fexplicit -frelaxed-rules --no-vital-checks --warn-binding --mb-comments
