# -*- tcl -*-

# Ignore Output path of registers named *tig_reg_d*
# Ignore Input path of registers named *tig_reg_q*
# Ignore Reset path of registers named *tig_reg_clr*
# Ignore Preset path of registers named *tig_reg_pre*
# Ignore path through nets named *async_net*
# Apply cross-region paths for registers named *cross_region_reg_d*
# Apply read-clock timings for TDP-Ram that were demoted to Registers

set_false_path -to [get_pins {*tig_reg_clr*/CLR}]
set_false_path -to [get_pins {*tig_reg_pre*/PRE}]
set_false_path -from [get_pins {*tig_reg_q*/Z}]
set_false_path -from [get_pins {*tig_reg_q*/O}]
set_false_path -from [get_pins {*tig_reg_q*/Q}]
set_false_path -to [get_pins {*tig_reg_d*/D}]
set_false_path -to [get_pins {*tig_reg_d*/I}]
set_false_path -from [get_pins {*tig_reg_q*}]
set_false_path -to [get_pins {*tig_reg_d*}]
set_false_path -through [get_nets {*_async_net*}]
