# The board oscillator, and what the PLL makes of it.
create_clock -name clk50m -period 20.000 [get_ports clk50m_i]

# TCK, at the 30 MHz acrobe drives this part at.  Quartus adds the
# altera_reserved_tck port itself when it inserts the SLD hub.
create_clock -name tck -period 33.333 [get_ports altera_reserved_tck]

# A bare tennm_ph2_iopll atom gets no clocks derived for it: the
# IOPLL IP's own SDC is what declares them there.  100 and 125 MHz off
# the 50 MHz pin.
create_generated_clock -name pll0 -source [get_ports clk50m_i] \
  -multiply_by 2 [get_pins {pll|inst|out_clk[0]}]
create_generated_clock -name pll1 -source [get_ports clk50m_i] \
  -multiply_by 5 -divide_by 2 [get_pins {pll|inst|out_clk[1]}]

derive_clock_uncertainty

# The SDM oscillator clocks nothing but the counter that measures it.
# Its rate is not published, so it is stated at the fastest the
# counter must survive.
create_clock -name internal -period 2.5 [get_pins -compatibility_mode {*internal*gen|clkout}]

# What comes back through the header pin: a square wave at the PLL's
# first rate.  It clocks nothing but the counter that measures it, and
# it arrives from outside the die.
create_clock -name ddr_loop -period 10.0 [get_ports ddr_loop_io]

set_clock_groups -asynchronous \
  -group [get_clocks {clk50m pll0 pll1}] \
  -group [get_clocks tck] \
  -group [get_clocks internal] \
  -group [get_clocks ddr_loop]

set_false_path -to [get_ports led_o[*]]
