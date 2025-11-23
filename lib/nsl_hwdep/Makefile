packages += clock
packages += jtag
packages += reset

ifneq ($(filter lattice-ice40,$(hwdep)),)
packages += ice40
endif

packages += uid
packages += config

ifneq ($(filter xilinx,$(hwdep)),)
packages += xadc
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

