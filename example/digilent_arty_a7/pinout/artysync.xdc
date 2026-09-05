# ArtySync rev. A shield on the arduino header, from the board
# netlist.  Signal names follow the shield nets.

# NEO-M8Q, D_SEL open/high: UART on TXD/RXD, DDC on SDA/SCL.
# gps_txd is GPS to FPGA, gps_rxd FPGA to GPS.
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { gps_sda_io }];
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { gps_scl_io }];
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { gps_txd_i }];
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { gps_rxd_o }];
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { gps_safeboot_n_o }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { gps_dsel_o }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { gps_pps_i }];
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { gps_extint_o }];
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { gps_reset_n_o }];

# 20 MHz VCXO through JP1 position B (the shield's Z7_MRCC route,
# shield pin A5): it lands on package pin D5, an SRCC, which reaches
# the region's MMCM.  Position A (shield D11, package U18) is not
# clock-capable on the A7 and stays unused.
set_property -dict { PACKAGE_PIN D5    IOSTANDARD LVCMOS33 } [get_ports { vcxo_clock_i }];

# MCP4726 DAC pulling the VCXO, on the dedicated I2C header pins.
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { xo_sda_io }];
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { xo_scl_io }];

# 10 MHz reference port: dir high (board pull-up default) drives the
# FIN1019 line side from the SMA toward ref10m_p/n, low reverses it.
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { ref10m_dir_o }];
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { ref10m_p_io }];
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { ref10m_n_io }];

# SMAs.
set_property -dict { PACKAGE_PIN F5    IOSTANDARD LVCMOS33 } [get_ports { aux_i }];
set_property -dict { PACKAGE_PIN E7    IOSTANDARD LVCMOS33 } [get_ports { pps_i }];
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { pps_o }];
