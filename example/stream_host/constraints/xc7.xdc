# Override the internal oscillator's derived frequency so place and
# route optimizes for the application target instead of the actual
# CFGMCLK rate.  156.25 MHz is 5G ethernet at the 4-byte stream width.
create_clock -name target_clk -period 6.4 [get_pins clk_gen/inst/CFGMCLK]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports { done_led_o }]
