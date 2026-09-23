ifneq ($(filter xilinx,$(hwdep)),)
ifneq ($(filter xc6%,$(target_part)),)
packages += xc6_config
endif
ifneq ($(filter xc7%,$(target_part)),)
packages += xc7_config
endif
endif

ifneq ($(filter gowin,$(hwdep)),)
packages += gowin_config
endif

ifneq ($(filter altera,$(hwdep)),)
ifneq ($(filter 10CL%,$(target_part)),)
packages += cyclone10lp_config
endif
endif
