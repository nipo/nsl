# Customization of transceiver_cluster_series7_ip_top: parameter ranges and
# value lists, one GUI group per lane, and lanes past lane_count_c hidden.
set core [ipx::current_core]
set page [ipgui::get_pagespec -name "Page 0" -component $core]

proc user_param {core name} {
    return [ipx::get_user_parameters $name -of_objects $core]
}

set p [user_param $core lane_count_c]
set_property display_name {Lane count} $p
set_property value_validation_type range_long $p
set_property value_validation_range_minimum 1 $p
set_property value_validation_range_maximum 4 $p

set p [user_param $core refclk_mhz_c]
set_property display_name {Reference clock (MHz)} $p
set_property value_validation_type range_long $p
set_property value_validation_range_minimum 10 $p
set_property value_validation_range_maximum 800 $p

set p [user_param $core line_rate_mbps_c]
set_property display_name {Line rate (Mb/s)} $p
set_property value_validation_type range_long $p
set_property value_validation_range_minimum 600 $p
set_property value_validation_range_maximum 1250 $p

set clocking [ipgui::add_group -name {Clocking} -component $core -parent $page -display_name {Clocking}]
ipgui::move_param -component $core -order 0 [ipgui::get_guiparamspec -name "lane_count_c" -component $core] -parent $page
ipgui::move_param -component $core -order 0 [ipgui::get_guiparamspec -name "refclk_mhz_c" -component $core] -parent $clocking
ipgui::move_param -component $core -order 1 [ipgui::get_guiparamspec -name "line_rate_mbps_c" -component $core] -parent $clocking

for {set i 0} {$i < 4} {incr i} {
    set p [user_param $core lane${i}_loopback_c]
    set_property display_name {Loopback} $p
    set_property value_validation_type list $p
    set_property value_validation_list {NONE NEAR_END_PCS NEAR_END_PMA FAR_END_PMA FAR_END_PCS} $p
    set_property display_name {Invert TX polarity} [user_param $core lane${i}_polarity_invert_tx_c]
    set_property display_name {Invert RX polarity} [user_param $core lane${i}_polarity_invert_rx_c]

    set group [ipgui::add_group -name "Lane $i" -component $core -parent $page -display_name "Lane $i"]
    set order 0
    foreach name [list lane${i}_loopback_c lane${i}_polarity_invert_tx_c lane${i}_polarity_invert_rx_c] {
        if {$i > 0} {
            set_property enablement_tcl_expr "\$lane_count_c > $i" [user_param $core $name]
        }
        ipgui::move_param -component $core -order $order [ipgui::get_guiparamspec -name $name -component $core] -parent $group
        incr order
    }

    if {$i == 0} {
        continue
    }

    foreach busif [list lane${i} lane${i}_tx lane${i}_rx lane${i}_clock_o lane${i}_reset_n_o lane${i}_pma_reset_n_i] {
        set_property enablement_dependency "\$lane_count_c > $i" [ipx::get_bus_interfaces $busif -of_objects $core]
    }
    foreach port [ipx::get_ports lane${i}_* -of_objects $core] {
        set_property enablement_dependency "\$lane_count_c > $i" $port
        if {[get_property direction $port] eq "in"} {
            if {[string match *reset_n_i [get_property name $port]] || [get_property name $port] eq "lane${i}_rx_ready_i"} {
                set_property driver_value 1 $port
            } else {
                set_property driver_value 0 $port
            }
        }
    }
}
