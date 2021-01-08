vhdl-sources += top.vhd
ifneq ($(filter xc7%,$(target)),)
constraint-sources += io.xdc
else
constraint-sources += io.ucf
endif
deps += nsl_line_coding.ibm_8b10b

