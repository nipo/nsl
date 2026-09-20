# The measurer counts the memory clock as a plain wire, sampled by the
# board clock.  That counting is the measurement it exists for, so
# there is nothing here for the tool to time between the two: cutting
# them apart is the intent, not a workaround.  Every other crossing in
# the design lands on a resynchroniser and the constraint generator
# writes those itself.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks board_clk] \
  -group [get_clocks -of_objects [get_pins -hierarchical -filter { NAME =~ *ram_pll*/CLKOUT* }]]

# Nothing here constrains the memory bus pins.
#
# Every one of them leaves from a serialiser that lives in the pad, so
# there is no placement for the tool to get wrong and no path from
# fabric to pin to bound.  What is left is the skew of the memory rate
# clock across the pads it reaches, which the tool reports under that
# clock rather than under the bus.
#
# That is an argument, not a measurement.  The SRAM bench on the
# Spartan-6 found a pad spread that wandered between 1.7 and 3.0 ns
# build to build until it was bounded, and on a source synchronous bus
# the spread is the margin.  Before this design is trusted at rate,
# the clock's skew across bank 16 wants reading out of the timing
# report and comparing against the part's setup and hold.

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
