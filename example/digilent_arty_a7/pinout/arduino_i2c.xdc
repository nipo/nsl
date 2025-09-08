set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { arduino_i2c_scl_io }];
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { arduino_i2c_sda_io }];
set_property -dict { PACKAGE_PIN A14   IOSTANDARD LVCMOS33 } [get_ports { arduino_i2c_scl_pu_o }];
set_property -dict { PACKAGE_PIN A13   IOSTANDARD LVCMOS33 } [get_ports { arduino_i2c_sda_pu_o }];
