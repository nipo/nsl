# Single-ended 0-3.3V inputs on the outer header, each on its own
# XADC auxiliary pair.
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[0].p }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[0].n }];
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[1].p }];
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[1].n }];
set_property -dict { PACKAGE_PIN K14   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[2].p }];
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[2].n }];
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[3].p }];
set_property -dict { PACKAGE_PIN J16   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[3].n }];
set_property -dict { PACKAGE_PIN J20   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[4].p }];
set_property -dict { PACKAGE_PIN H20   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[4].n }];
set_property -dict { PACKAGE_PIN G19   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[5].p }];
set_property -dict { PACKAGE_PIN G20   IOSTANDARD LVCMOS33 } [get_ports { arduino_a_i[5].n }];
