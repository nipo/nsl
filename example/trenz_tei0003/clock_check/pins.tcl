# CYC1000 (TEI0003) pins this bench uses, and the settings the board
# needs around them.

# Every bank of this board runs at 3.3 V.
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

# A Cyclone's default for a pin nothing in the design drives is to
# drive it to ground, and this part reaches an SDRAM, an accelerometer
# and four FT2232H pins two of which are driven as modem lines.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# 12 MHz oscillator, the reference of the PLL and the clock the
# transport rides.
set_location_assignment PIN_M2 -to clk12m_i

# FT2232H channel B.  BDBUS0 is the FTDI's TXD and BDBUS1 its RXD, so
# the first is an input of the FPGA and the second an output.
set_location_assignment PIN_R7 -to uart_rx_i
set_location_assignment PIN_T7 -to uart_tx_o

# PIO_01 of the user header, which nothing else on the board reaches.
set_location_assignment PIN_F13 -to ddr_loop_io

set_location_assignment PIN_M6 -to led_o[0]
set_location_assignment PIN_T4 -to led_o[1]
set_location_assignment PIN_T3 -to led_o[2]
set_location_assignment PIN_R3 -to led_o[3]
set_location_assignment PIN_T2 -to led_o[4]
set_location_assignment PIN_R4 -to led_o[5]
set_location_assignment PIN_N5 -to led_o[6]
set_location_assignment PIN_N3 -to led_o[7]
