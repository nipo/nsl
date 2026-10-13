# Without indep_rx_clock_c the whole phy runs on clock_i, but to_mac is
# declared against rx_clock_i, which ports.tcl disables in that
# configuration. Its clock properties therefore never propagate. Copy
# them across from clock_i by hand.
proc post_propagate {cellpath otherinfo} {
    set ip [get_bd_cells $cellpath]

    if { [string is true -strict [get_property CONFIG.indep_rx_clock_c $ip]] } {
        return
    }

    set freq   [get_property CONFIG.FREQ_HZ    [get_bd_pins ${cellpath}/clock_i]]
    set domain [get_property CONFIG.CLK_DOMAIN [get_bd_pins ${cellpath}/clock_i]]

    set pin [get_bd_intf_pins -quiet ${cellpath}/to_mac]
    if { $pin eq "" } { return }
    if { $freq ne "" }   { set_property CONFIG.FREQ_HZ    $freq   $pin }
    if { $domain ne "" } { set_property CONFIG.CLK_DOMAIN $domain $pin }
}
