# The design runs on the PLL output; the board files only constrain
# the input port, so without this the tool assumes a default rate for
# it and never optimizes for the real one.
create_clock -name clock_core -period 10.0 [get_nets {clock_s}]
