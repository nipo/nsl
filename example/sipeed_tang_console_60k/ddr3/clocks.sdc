# The four clocks the memory block makes, the one the transport runs
# on, and the buffered board clock they all come from.
#
# Each is stated at the pin that drives it rather than at a net the
# design names: the four outputs of one block arrive as one vector and
# the scalar each is read out of does not survive synthesis, while a
# primitive's output pin is a name the netlist keeps.  The tool derives
# a clock at each of these pins by itself and puts a default rate on
# it; what these do is give it the rate the design was built for.
#
# The two shifted outputs are a quarter of a memory period behind their
# partners, which is a sixteenth of a controller cycle on the pair the
# strobe's group crosses between.  Stating the phase would be stating
# the crossing, and the crossing does not need stating: it is two edges
# of one clock, which the engine times by itself.  What these say is
# only the rate.
create_clock -name board -period 20.0 -waveform {0 10} [get_pins {board_buffer/is_global.buf/CLKOUT}]
create_clock -name mem -period 10.0 -waveform {0 5} [get_pins {ram_pll/use_plla.inst/CLKOUT0}]
create_clock -name mem_fast -period 2.5 -waveform {0 1.25} [get_pins {ram_pll/use_plla.inst/CLKOUT1}]
create_clock -name mem_data -period 2.5 -waveform {0 1.25} [get_pins {ram_pll/use_plla.inst/CLKOUT2}]
create_clock -name mem_shifted -period 10.0 -waveform {0 5} [get_pins {ram_pll/use_plla.inst/CLKOUT3}]
create_clock -name usb -period 16.666 -waveform {0 8.333} [get_pins {usb_pll/has_pll.inst/use_plla.inst/CLKOUT0}]

# The rack sits on the transport's clock and every instrument reaches
# its own domain through a resynchroniser, and the rate measurer counts
# the memory clock as a plain wire sampled by the board clock -- that
# counting is the measurement it exists for.  So there is nothing here
# for the tool to time between these groups.
#
# Nothing cuts the memory group apart: the strobe's pins leave on the
# shifted pair and are read back on it, the data's on the unshifted
# one, and what crosses between the two is paths the engine has both
# ends of.
set_clock_groups -asynchronous -group [get_clocks {mem mem_fast mem_data mem_shifted}] -group [get_clocks {usb}] -group [get_clocks {board clk_50}]

# Nothing here constrains the memory bus pins.
#
# Every one of them leaves from a serialiser that lives in the pad, so
# there is no placement for the tool to get wrong and no path from
# fabric to pin to bound.  What is left is the skew of the memory rate
# clock across the pads it reaches, which the tool reports under that
# clock rather than under the bus.

# Two things the engine times that are not paths, each cut with the
# reason rather than to make a number go green.
#
# The panel's whole-slot knobs used to be a third: the PHY read the
# slip, the leads, the offset and the strobe's sense combinationally
# into every serialiser's word, so a knob that moved crossed the die
# from the rack and then a sixteen way mux per bit of every pin.  The
# PHY registers them at its own input now, so what would be left to cut
# is that register into the same mux -- 10.3 ns against a cycle of 10,
# where it used to be 11.6.  It is left timed: cutting it was measured
# and made the rest of the domain worse, and what it says while it
# fails is a number this bench wants to carry rather than hide.  The
# readme has both readings.

# The memory bus, as it reaches every capture serialiser.  A pin's data
# input here has exactly two sources: the pad, which carries a bus no
# clock of this design has ever heard of and which is placed by the
# read training rather than by the tools, and the delay line's tap
# value, which is a position and not data.  The tap moves only while a
# host is walking the line, and no instrument reads on the cycle it
# steps -- every sweep settles between a step and a reading.  Left in,
# this is the whole of the memory domain's negative slack: the tap
# register sits in the controller domain, the IODELAY it feeds adds
# most of a nanosecond, and the serialiser behind it samples at the
# memory rate.
set_false_path -to [get_pins {*listener/p8.inst/D}]

# The memory domain's own reset, as it reaches the pads' serialisers.
# It is released asynchronously and every one of these primitives has
# its own reset input, so what the engine is timing is a release with
# nothing waiting on it.  NSL's generated constraints already cut this
# register's fabric fanout, at `*tig_reg_clr*/CLEAR`; a Gowin
# primitive calls the same pin RESET and so escapes that rule.
set_false_path -from [get_pins {*tig_reg_clr*/Q}] -to [get_pins {*/RESET}]
