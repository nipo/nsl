GHDL=ghdl
ghdl-backend:=$(shell "$(GHDL)" --version | grep "code generator" | cut -d' ' -f2)
GHDL_LLVM:=$(if $(filter $(ghdl-backend),GCC gcc llvm),1,)
target-usage = simulation
source-types += vhpidirect vpi
