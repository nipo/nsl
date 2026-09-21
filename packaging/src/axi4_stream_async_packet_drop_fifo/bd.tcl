# With clock_count_c = 1 the fifo runs on in_clock_i, but the out
# interface is declared against out_clock_i, which ports.tcl disables in
# that configuration.  Its clock properties therefore never propagate.
# Copy them across from in_clock_i by hand.
proc post_propagate {cellpath otherinfo} {
    set ip [get_bd_cells $cellpath]

    if { [get_property CONFIG.clock_count_c $ip] != 1 } {
        return
    }

    set freq   [get_property CONFIG.FREQ_HZ    [get_bd_pins ${cellpath}/in_clock_i]]
    set domain [get_property CONFIG.CLK_DOMAIN [get_bd_pins ${cellpath}/in_clock_i]]

    set pin [get_bd_intf_pins -quiet ${cellpath}/out]
    if { $pin eq "" } { return }
    if { $freq ne "" }   { set_property CONFIG.FREQ_HZ    $freq   $pin }
    if { $domain ne "" } { set_property CONFIG.CLK_DOMAIN $domain $pin }
}
