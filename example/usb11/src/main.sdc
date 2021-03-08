#   define_global_attribute syn_global_buffers 1
create_clock -name clk_16 -period 62.5 [get_ports {clk16_i}]
create_clock -name clk_48 -period 20.833 [get_pins {pll.inst_core_global_inst/plloutglobal}]

set_false_path -from [get_ports {usb_d*}] -to clk_16

