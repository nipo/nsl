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

# 50 MHz oscillator, CLOCK0_50 on a 1.1 V bank.  CLOCK1_50 on V16

set_location_assignment PIN_DJ35 -to clock_50_i
set_instance_assignment -name IO_STANDARD "1.1-V" -to clock_50_i
set_location_assignment PIN_DF35 -to led_o[0]
set_instance_assignment -name IO_STANDARD "1.1-V" -to led_o[0]
set_location_assignment PIN_DJ32 -to led_o[1]
set_instance_assignment -name IO_STANDARD "1.1-V" -to led_o[1]

set_location_assignment PIN_BC64 -to hps_usb_clk_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_clk_i
set_location_assignment PIN_BC67 -to hps_usb_stp_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_stp_o
set_location_assignment PIN_AY67 -to hps_usb_dir_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_dir_i
set_location_assignment PIN_AN72 -to hps_usb_data_io[0]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[0]
set_location_assignment PIN_AY69 -to hps_usb_data_io[1]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[1]
set_location_assignment PIN_BA75 -to hps_usb_nxt_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_nxt_i
set_location_assignment PIN_BC71 -to hps_usb_data_io[2]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[2]
set_location_assignment PIN_AU74 -to hps_usb_data_io[3]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[3]
set_location_assignment PIN_AY71 -to hps_usb_data_io[4]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[4]
set_location_assignment PIN_AU75 -to hps_usb_data_io[5]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[5]
set_location_assignment PIN_BC72 -to hps_usb_data_io[6]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[6]
set_location_assignment PIN_BP74 -to hps_usb_data_io[7]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_usb_data_io[7]
set_location_assignment PIN_BP75 -to hps_enet_tx_clk_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_clk_o
set_location_assignment PIN_BL74 -to hps_enet_tx_ctl_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_ctl_o
set_location_assignment PIN_BL75 -to hps_enet_rx_clk_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_clk_i
set_location_assignment PIN_AP74 -to hps_enet_rx_ctl_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_ctl_i
set_location_assignment PIN_BG74 -to hps_enet_tx_data_o[0]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_data_o[0]
set_location_assignment PIN_AP75 -to hps_enet_tx_data_o[1]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_data_o[1]
set_location_assignment PIN_BD74 -to hps_enet_rx_data_i[0]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_data_i[0]
set_location_assignment PIN_AN71 -to hps_enet_rx_data_i[1]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_data_i[1]
set_location_assignment PIN_BD75 -to hps_enet_tx_data_o[2]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_data_o[2]
set_location_assignment PIN_AM74 -to hps_enet_tx_data_o[3]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_tx_data_o[3]
set_location_assignment PIN_AJ74 -to hps_enet_rx_data_i[2]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_data_i[2]
set_location_assignment PIN_AJ75 -to hps_enet_rx_data_i[3]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_rx_data_i[3]
set_location_assignment PIN_AF75 -to hps_sd_data_io[0]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_data_io[0]
set_location_assignment PIN_AC75 -to hps_sd_data_io[1]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_data_io[1]
set_location_assignment PIN_AC74 -to hps_sd_clk_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_clk_o
set_location_assignment PIN_AN67 -to hps_clk_25_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_clk_25_i
set_location_assignment PIN_Y75 -to hps_gsensor_int_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_gsensor_int_io
set_location_assignment PIN_AN64 -to hps_sd_data_io[2]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_data_io[2]
set_location_assignment PIN_Y74 -to hps_sd_data_io[3]
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_data_io[3]
set_location_assignment PIN_AK69 -to hps_sd_cmd_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_sd_cmd_io
set_location_assignment PIN_P75 -to hps_gsensor_i2c_en_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_gsensor_i2c_en_io
set_location_assignment PIN_L75 -to hps_i2c_sda_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_i2c_sda_io
set_location_assignment PIN_N72 -to hps_i2c_scl_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_i2c_scl_io
set_location_assignment PIN_N71 -to hps_uart_tx_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_uart_tx_o
set_location_assignment PIN_AD72 -to hps_uart_rx_i
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_uart_rx_i
set_location_assignment PIN_F75 -to hps_key_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_key_io
set_location_assignment PIN_AD71 -to hps_led_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_led_io
set_location_assignment PIN_C74 -to hps_enet_mdio_io
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_mdio_io
set_location_assignment PIN_D71 -to hps_enet_mdc_o
set_instance_assignment -name IO_STANDARD "1.8-V" -to hps_enet_mdc_o
