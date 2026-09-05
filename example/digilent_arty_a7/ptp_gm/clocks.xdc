# The VCXO reference on the shield.
create_clock -period 50.000 -name vcxo_clk [get_ports { vcxo_clock_i }]
# The same VCXO on the as-fabricated JP1 route, a plain IO pin: it
# only feeds a rate counter, routed through the fabric without a
# global buffer.
create_clock -period 50.000 -name vcxo_a_clk [get_ports { vcxo_a_clock_i }]
set_property CLOCK_BUFFER_TYPE NONE [get_ports { vcxo_a_clock_i }]

# MII clocks from the PHY.
create_clock -period 40.000 -name eth_rx_clk [get_ports { eth_rx_clk_i }]
create_clock -period 40.000 -name eth_tx_clk [get_ports { eth_tx_clk_i }]

# Every domain pair crosses through explicit synchronizers.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks sys_clk_pin] \
  -group [get_clocks -include_generated_clocks vcxo_clk] \
  -group [get_clocks vcxo_a_clk] \
  -group [get_clocks eth_rx_clk] \
  -group [get_clocks eth_tx_clk]

# The VCXO clock forwarded to the 10 MHz port pair, into the FIN1019
# termination.
set_property DRIVE 4 [get_ports { ref10m_p_io ref10m_n_io }]
set_property SLEW SLOW [get_ports { ref10m_p_io ref10m_n_io }]
