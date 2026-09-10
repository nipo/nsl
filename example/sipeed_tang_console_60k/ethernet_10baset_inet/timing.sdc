# The line clock carries the MAU and the analyzer, the core clock the
# stack.  Without these the tool assumes a default rate for the nets
# behind the buffer and the PLL, and never optimizes for the real
# ones.
create_clock -name clock_line -period 10.0 [get_nets {clock_line_s}]
create_clock -name clock_core -period 20.0 [get_nets {clock_ext_s}]

# The two domains only meet through dual-clock stream fifos, so paths
# between them carry no timing requirement.
set_clock_groups -asynchronous -group [get_clocks {clock_line}] -group [get_clocks {clock_core}]
