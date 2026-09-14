# The ATSHA204A sits on a one-wire-over-I2C-sda bus of its own: only
# the data line reaches the FPGA.
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { crypto_sda_io }];
