set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.miso }];
set_property -dict { PACKAGE_PIN T12   IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.mosi }];
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.sck }];
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.cs_n }];
