# The four shifted clocks reach the analyzer as plain wires, sampled
# by a clock the other block makes.  That sampling is the measurement
# the design exists for, so there is nothing here for the tool to
# time: cutting the two groups apart is the whole intent, not a
# workaround.
set_clock_groups -asynchronous \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter { NAME =~ *phase_pll*/CLKOUT* }]] \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter { NAME =~ *sample_pll*/CLKOUT* }]]
