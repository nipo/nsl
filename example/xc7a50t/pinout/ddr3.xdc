# DDR3L on bank 16, an AS4C128M8D3LB: one byte lane, one strobe pair.
#
# The clock and the strobe are true pairs, each off one buffer; the
# strobe's is bidirectional so that the board can read back what it
# drives.  Two
# ordinary pins driven against each other would carry the same
# information and move their crossing point by whatever their routing
# differs by, which is what the part reads them from.
#
# The bank's reference comes from the board.  DDRVREF, a 1k/1k divider
# of VDDQ, feeds both VREF pins of bank 16, D15 and C20, and the part's
# VREFCA and VREFDQ with them.  Selecting the internal reference would
# leave those two pins as unused IO, which take the bitstream's default
# pull-down and load the divider the part is reading its own reference
# from, so the bank takes the pins.

# Address
set_property -dict { PACKAGE_PIN E14 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[0] }]
set_property -dict { PACKAGE_PIN G21 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[1] }]
set_property -dict { PACKAGE_PIN D14 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[2] }]
set_property -dict { PACKAGE_PIN A20 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[3] }]
set_property -dict { PACKAGE_PIN G22 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[4] }]
set_property -dict { PACKAGE_PIN D21 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[5] }]
set_property -dict { PACKAGE_PIN D22 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[6] }]
set_property -dict { PACKAGE_PIN A21 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[7] }]
set_property -dict { PACKAGE_PIN E22 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[8] }]
set_property -dict { PACKAGE_PIN F18 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[9] }]
set_property -dict { PACKAGE_PIN D16 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[10] }]
set_property -dict { PACKAGE_PIN B22 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[11] }]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[12] }]
set_property -dict { PACKAGE_PIN F19 IOSTANDARD SSTL135 } [get_ports { ddr3_addr[13] }]

# Bank address
set_property -dict { PACKAGE_PIN B20 IOSTANDARD SSTL135 } [get_ports { ddr3_ba[0] }]
set_property -dict { PACKAGE_PIN F20 IOSTANDARD SSTL135 } [get_ports { ddr3_ba[1] }]
set_property -dict { PACKAGE_PIN F14 IOSTANDARD SSTL135 } [get_ports { ddr3_ba[2] }]

# Command
set_property -dict { PACKAGE_PIN F15 IOSTANDARD SSTL135 } [get_ports { ddr3_ras_n }]
set_property -dict { PACKAGE_PIN A18 IOSTANDARD SSTL135 } [get_ports { ddr3_cas_n }]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD SSTL135 } [get_ports { ddr3_we_n }]
set_property -dict { PACKAGE_PIN B21 IOSTANDARD SSTL135 } [get_ports { ddr3_reset_n }]
set_property -dict { PACKAGE_PIN A19 IOSTANDARD SSTL135 } [get_ports { ddr3_cs_n[0] }]
set_property -dict { PACKAGE_PIN E13 IOSTANDARD SSTL135 } [get_ports { ddr3_cke[0] }]
set_property -dict { PACKAGE_PIN D20 IOSTANDARD SSTL135 } [get_ports { ddr3_odt[0] }]

# Clock
set_property -dict { PACKAGE_PIN C14 IOSTANDARD DIFF_SSTL135 } [get_ports { ddr3_ck_p[0] }]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD DIFF_SSTL135 } [get_ports { ddr3_ck_n[0] }]

# Data
set_property -dict { PACKAGE_PIN C13 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[0] }]
set_property -dict { PACKAGE_PIN B13 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[1] }]
set_property -dict { PACKAGE_PIN A13 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[2] }]
set_property -dict { PACKAGE_PIN B17 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[3] }]
set_property -dict { PACKAGE_PIN B16 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[4] }]
set_property -dict { PACKAGE_PIN B18 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[5] }]
set_property -dict { PACKAGE_PIN A14 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[6] }]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD SSTL135 } [get_ports { ddr3_dq[7] }]
set_property -dict { PACKAGE_PIN B15 IOSTANDARD SSTL135 } [get_ports { ddr3_dm[0] }]

# Strobe
set_property -dict { PACKAGE_PIN A15 IOSTANDARD DIFF_SSTL135 } [get_ports { ddr3_dqs_p[0] }]
set_property -dict { PACKAGE_PIN A16 IOSTANDARD DIFF_SSTL135 } [get_ports { ddr3_dqs_n[0] }]
