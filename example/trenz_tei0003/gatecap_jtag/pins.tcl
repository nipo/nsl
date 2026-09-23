# CYC1000 (TEI0003) pins this bench uses, and the settings the board
# needs around them.

# Every bank of this board runs at 3.3 V.
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

# A Cyclone's default for a pin nothing in the design drives is to
# drive it to ground.  Half of what this part's pins reach is driven
# from the other side -- the SDRAM's data bus, the accelerometer, and
# the six channel-B pins this design leaves alone, some of which the
# FT2232H drives -- so the default would put the FPGA
# in contention with them.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# 12 MHz oscillator, the only clock here.
set_location_assignment PIN_M2 -to clk12m_i

# The altera_reserved_* JTAG ports need no assignment: Quartus puts
# them on the dedicated JTAG pads.

set_location_assignment PIN_M6 -to led_o[0]
set_location_assignment PIN_T4 -to led_o[1]
set_location_assignment PIN_T3 -to led_o[2]
set_location_assignment PIN_R3 -to led_o[3]
set_location_assignment PIN_T2 -to led_o[4]
set_location_assignment PIN_R4 -to led_o[5]
set_location_assignment PIN_N5 -to led_o[6]
set_location_assignment PIN_N3 -to led_o[7]

set_location_assignment PIN_N6 -to user_btn_i
