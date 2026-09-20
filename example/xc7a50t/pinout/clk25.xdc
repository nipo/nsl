# A crystal oscillator on bank 15, which the DDR3 bank does not share.
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports { clk_25_i }]
create_clock -add -name board_clk -period 40.00 -waveform {0 20} [get_ports { clk_25_i }]
