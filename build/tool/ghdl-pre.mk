GHDL=ghdl
ghdl-flavor:=$(shell "$(GHDL)" --version | grep "code generator" | cut -d' ' -f2 | tr A-Z a-z)
GHDL_LLVM:=$(if $(filter $(ghdl-flavor),gcc llvm),1,)
target-usage = simulation
source-types += vhpidirect vpi
