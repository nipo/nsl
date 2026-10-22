proc init {cellpath otherInfo} {
    set ip [get_bd_cells $cellpath]
    bd::mark_propagate_overrideable $ip "clock_freq_hz"
}

proc post_propagate {cellpath otherInfo} {
    set ip [get_bd_cells $cellpath]
    
    set clk_pin [get_bd_pins $cellpath/clock]
    
    if {$clk_pin != ""} {
        set propagated_freq [get_property CONFIG.FREQ_HZ $clk_pin]
        
        if {$propagated_freq != ""} {
            set_property CONFIG.clock_freq_hz $propagated_freq $ip
        }
    }
}
