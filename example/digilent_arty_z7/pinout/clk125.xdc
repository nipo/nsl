set_property -dict { PACKAGE_PIN H16    IOSTANDARD LVCMOS33 } [get_ports { clock_125_i }];
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { clock_125_i }];
