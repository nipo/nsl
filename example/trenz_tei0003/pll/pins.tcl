# CYC1000 (TEI0003) pins this design uses.

set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# 12 MHz oscillator, the reference of the PLL below.
set_location_assignment PIN_M2 -to clk12m_i

set_location_assignment PIN_M6 -to led_o[0]
set_location_assignment PIN_T4 -to led_o[1]
