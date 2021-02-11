create_clock -name usb_clock -period 16.66 [get_ports phy_clk]

set CLKs_max 0.200
set CLKs_min 0.100
set CLKd_max 0.200
set CLKd_min 0.100
set tSU 0.125
set tH 0.100
set BD_max 0.060
set BD_min 0.060

set_output_delay -clock usb_clock -max [expr $CLKs_max + $BD_max + $tSU - $CLKd_min] [get_ports {phy_data[*] phy_stp}]
set_output_delay -clock usb_clock -min [expr $CLKs_min + $BD_min - $tH - $CLKd_max] [get_ports {phy_data[*] phy_stp}]

set_input_delay -clock usb_clock -max [expr $CLKs_max + $BD_max + $tSU - $CLKd_min] [get_ports {phy_data[*] phy_nxt phy_dir}]
set_input_delay -clock usb_clock -min [expr $CLKs_min + $BD_min - $tH - $CLKd_max] [get_ports {phy_data[*] phy_nxt phy_dir}]
