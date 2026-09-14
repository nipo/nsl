# The inner header carries 0-1.0V differential inputs: one XADC pair
# per two shield pins, the even one positive.
set_property -dict { PACKAGE_PIN F19   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[6].p  }];
set_property -dict { PACKAGE_PIN F20   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[7].n  }];
set_property -dict { PACKAGE_PIN C20   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[8].p  }];
set_property -dict { PACKAGE_PIN B20   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[9].n  }];
set_property -dict { PACKAGE_PIN B19   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[10].p }];
set_property -dict { PACKAGE_PIN A20   IOSTANDARD LVCMOS33 } [get_ports { arduino_ext_a_i[11].n }];
