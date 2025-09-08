set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.miso }];
set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.mosi }];
set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.sck }];
set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { arduino_spi_io.cs_n }];
