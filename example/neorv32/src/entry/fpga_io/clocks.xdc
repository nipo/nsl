set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

create_clock -period 16.666		-name osc_clock			[get_ports {clock_60_i}]
create_generated_clock -name phy_clock -source [get_ports {clock_60_i}] -divide_by 1  [get_ports phy_clk_o]

set_input_delay -clock phy_clock -max 6.000 [get_ports {phy_data_io[*] phy_dir_i phy_nxt_i}]
set_input_delay -clock phy_clock -min 0.500 [get_ports {phy_data_io[*] phy_dir_i phy_nxt_i}]
set_output_delay -clock phy_clock -max 3.000  [get_ports {phy_data_io[*] phy_stp_o phy_reset_n_o}]
set_output_delay -clock phy_clock -min  0.000 [get_ports {phy_data_io[*] phy_stp_o phy_reset_n_o}]
