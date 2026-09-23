# The board oscillator, and what the PLL makes of it.
#
# Two domains run here and the split is deliberate: the transport and
# the rack ride the oscillator, the controller and the walker ride the
# PLL.  The panel crosses between them, which is what the rack's own
# resynchronisers are for.
create_clock -name clk12m -period 83.333 [get_ports clk12m_i]

derive_pll_clocks
derive_clock_uncertainty

# The memory clock as the part sees it.  A DDR output handed the two
# constant halves of a forwarded clock puts the fabric's clock on the
# pin inverted, which is what -invert states: the part's edges fall
# half a period behind the ones that launched the pins beside them,
# and that half period is the setup and the hold the bus is driven
# with.
create_generated_clock -name ram_clk \
  -source [get_pins {ram_pll|inst|auto_generated|pll1|clk[0]}] \
  -invert [get_ports ram_clock_o]

# What the W9864G6JT asks of the pins it is driven on, against that
# forwarded clock.  Address, command and write data all carry the
# same 1.5 ns of setup and 1 ns of hold.
set ram_driven [get_ports {ram_cke_o ram_cs_n_o ram_ras_n_o ram_cas_n_o \
                           ram_we_n_o ram_ba_o[*] ram_a_o[*] ram_dqm_o[*] \
                           ram_dq_io[*]}]
set_output_delay -clock ram_clk -max 1.5 $ram_driven
set_output_delay -clock ram_clk -min -1.0 $ram_driven

# What it answers with: valid at worst 6 ns after the edge it was
# asked on at CAS latency 2, and held for 3 ns past the next one.
set_input_delay -clock ram_clk -max 6.0 [get_ports {ram_dq_io[*]}]
set_input_delay -clock ram_clk -min 3.0 [get_ports {ram_dq_io[*]}]

# The UART line is another chip's, resynchronised behind the port, and
# the LEDs answer to nobody's clock.
set_false_path -from [get_ports uart_rx_i]
set_false_path -to [get_ports uart_tx_o]
set_false_path -to [get_ports led_o[*]]
