# CYC1000 (TEI0003) pins this bench uses, and the settings the board
# needs around them.
#
# The memory pins are Trenz's own assignment, from
# ../pinout/TEI0003_pin_assignments.tcl.  A12 and A13 are not in it:
# the part has twelve row bits and the package does not bond the
# other two.

# Every bank of this board runs at 3.3 V.
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"

# A Cyclone's default for a pin nothing in the design drives is to
# drive it to ground.  This design leaves the accelerometer, the ADC,
# the user header and four FT2232H pins alone, two of which the FTDI
# drives as modem lines, so the default would put the FPGA in
# contention with all of them.
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# 12 MHz oscillator.  It is the PLL's reference, and it is also the
# only clock the transport and the rack ever see: an instrument whose
# own clock comes from the thing it measures cannot report that thing
# being wrong.
set_location_assignment PIN_M2 -to clk12m_i

# FT2232H channel B.  BDBUS0 is the FTDI's TXD and BDBUS1 its RXD, so
# the first is an input of the FPGA and the second an output.
set_location_assignment PIN_R7 -to uart_rx_i
set_location_assignment PIN_T7 -to uart_tx_o

set_location_assignment PIN_M6 -to led_o[0]
set_location_assignment PIN_T4 -to led_o[1]
set_location_assignment PIN_T3 -to led_o[2]
set_location_assignment PIN_R3 -to led_o[3]
set_location_assignment PIN_T2 -to led_o[4]
set_location_assignment PIN_R4 -to led_o[5]
set_location_assignment PIN_N5 -to led_o[6]
set_location_assignment PIN_N3 -to led_o[7]

set_location_assignment PIN_B14 -to ram_clock_o
set_location_assignment PIN_F8 -to ram_cke_o
set_location_assignment PIN_A6 -to ram_cs_n_o
set_location_assignment PIN_B7 -to ram_ras_n_o
set_location_assignment PIN_C8 -to ram_cas_n_o
set_location_assignment PIN_A7 -to ram_we_n_o

set_location_assignment PIN_A4 -to ram_ba_o[0]
set_location_assignment PIN_B6 -to ram_ba_o[1]

set_location_assignment PIN_A3 -to ram_a_o[0]
set_location_assignment PIN_B5 -to ram_a_o[1]
set_location_assignment PIN_B4 -to ram_a_o[2]
set_location_assignment PIN_B3 -to ram_a_o[3]
set_location_assignment PIN_C3 -to ram_a_o[4]
set_location_assignment PIN_D3 -to ram_a_o[5]
set_location_assignment PIN_E6 -to ram_a_o[6]
set_location_assignment PIN_E7 -to ram_a_o[7]
set_location_assignment PIN_D6 -to ram_a_o[8]
set_location_assignment PIN_D8 -to ram_a_o[9]
set_location_assignment PIN_A5 -to ram_a_o[10]
set_location_assignment PIN_E8 -to ram_a_o[11]

set_location_assignment PIN_B13 -to ram_dqm_o[0]
set_location_assignment PIN_D12 -to ram_dqm_o[1]

set_location_assignment PIN_B10 -to ram_dq_io[0]
set_location_assignment PIN_A10 -to ram_dq_io[1]
set_location_assignment PIN_B11 -to ram_dq_io[2]
set_location_assignment PIN_A11 -to ram_dq_io[3]
set_location_assignment PIN_A12 -to ram_dq_io[4]
set_location_assignment PIN_D9 -to ram_dq_io[5]
set_location_assignment PIN_B12 -to ram_dq_io[6]
set_location_assignment PIN_C9 -to ram_dq_io[7]
set_location_assignment PIN_D11 -to ram_dq_io[8]
set_location_assignment PIN_E11 -to ram_dq_io[9]
set_location_assignment PIN_A15 -to ram_dq_io[10]
set_location_assignment PIN_E9 -to ram_dq_io[11]
set_location_assignment PIN_D14 -to ram_dq_io[12]
set_location_assignment PIN_F9 -to ram_dq_io[13]
set_location_assignment PIN_C14 -to ram_dq_io[14]
set_location_assignment PIN_A14 -to ram_dq_io[15]
