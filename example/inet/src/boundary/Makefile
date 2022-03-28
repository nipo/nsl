vhdl-sources += fpga_io.vhd

ifeq ($(board),arty_a7)
constraint-sources += $(SRC_DIR)/arty_a7_35.xdc
endif

ifeq ($(board),s6_mockup)
constraint-sources += $(SRC_DIR)/s6_mockup.ucf
endif

ifeq ($(board),gw2a_18c_mockup)
constraint-sources += $(SRC_DIR)/io.cst
sdc-sources += $(SRC_DIR)/timings.sdc
endif

ifeq ($(board),gw1n_9c_mockup)
constraint-sources += $(SRC_DIR)/io.cst
sdc-sources += $(SRC_DIR)/timings.sdc
endif

deps += work.func
deps += nsl_hwdep.reset
deps += nsl_smi.smi
deps += nsl_clocking.pll
deps += nsl_io.clock

