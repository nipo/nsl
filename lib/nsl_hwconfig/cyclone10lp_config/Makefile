ifneq ($(filter 10CL%,$(target_part)),)
vhdl-sources += cyclone10lp_config.pkg.vhd

# Altera states the speed grade inside the ordering code rather than
# beside it, so the grade is read off the part number: 10CL025YU256C8G
# is a -C8 part.  A part number none of these branches claims leaves
# the package body out, and the design then fails to build rather than
# silently taking some other grade's limits.
ifneq ($(filter %C6G,$(target_part))$(filter %C6,$(target_part)),)
vhdl-sources += cyclone10lp_config_c6.vhd
else ifneq ($(filter %I7G,$(target_part))$(filter %I7,$(target_part)),)
vhdl-sources += cyclone10lp_config_i7.vhd
else ifneq ($(filter %A7G,$(target_part))$(filter %A7,$(target_part)),)
vhdl-sources += cyclone10lp_config_a7.vhd
else ifneq ($(filter %C8G,$(target_part))$(filter %C8,$(target_part)),)
vhdl-sources += cyclone10lp_config_c8.vhd
else ifneq ($(filter %I8G,$(target_part))$(filter %I8,$(target_part)),)
vhdl-sources += cyclone10lp_config_i8.vhd
endif
endif
