# The board oscillator.
create_clock -name clk50m -period 20.000 [get_ports clk50m_i]

# TCK, at the 30 MHz acrobe drives this part at.  Quartus adds the
# altera_reserved_tck port itself when it inserts the SLD hub.  The
# transport crosses TCK to the oscillator in its own FIFOs.
create_clock -name tck -period 33.333 [get_ports altera_reserved_tck]
set_clock_groups -asynchronous -group {clk50m} -group {tck}

derive_clock_uncertainty

# The LEDs and the key answer to nobody's clock.
set_false_path -from [get_ports key_n_i]
set_false_path -to [get_ports led_o[*]]
