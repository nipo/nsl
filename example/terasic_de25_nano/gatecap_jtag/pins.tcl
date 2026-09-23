# DE25-Nano pins this bench uses, and the settings the board needs
# around them, as Terasic's golden top states them.

# Configuration and power management, which the SDM needs to come up
# on this board.
set_global_assignment -name USE_CONF_DONE SDM_IO16
set_global_assignment -name USE_HPS_COLD_RESET SDM_IO11
set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "ACTIVE SERIAL X4"
set_global_assignment -name ACTIVE_SERIAL_CLOCK AS_FREQ_125MHZ
set_global_assignment -name DEVICE_INITIALIZATION_CLOCK OSC_CLK_1_125MHZ
set_global_assignment -name PWRMGT_VOLTAGE_OUTPUT_FORMAT "LINEAR FORMAT"
set_global_assignment -name PWRMGT_LINEAR_FORMAT_N "-12"

# Leave everything this design does not name alone.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# 50 MHz oscillator, on a 3.3 V bank.
set_location_assignment PIN_V16 -to clk50m_i
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to clk50m_i

set_location_assignment PIN_DF35 -to led_o[0]
set_location_assignment PIN_DJ32 -to led_o[1]
set_location_assignment PIN_DN22 -to led_o[2]
set_location_assignment PIN_DP23 -to led_o[3]
set_location_assignment PIN_DN25 -to led_o[4]
set_location_assignment PIN_DP25 -to led_o[5]
set_location_assignment PIN_DJ27 -to led_o[6]
set_location_assignment PIN_DP30 -to led_o[7]
set_instance_assignment -name IO_STANDARD "1.1-V" -to led_o[*]

# KEY0, low when pressed.
set_location_assignment PIN_C8 -to key_n_i
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to key_n_i
