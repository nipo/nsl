# The line clock carries the MAU, the timestamping and the time base,
# the core clock the stack, the servo and the screen, the USB clock
# the Full Speed phy and the gatecap rack.  Without these
# the tool assumes a default rate for the nets behind the buffer and
# the PLL, and never optimizes for the real ones.
create_clock -name clock_line -period 10.0 [get_nets {clock_line_s}]
create_clock -name clock_core -period 20.0 [get_nets {clock_ext_s}]
create_clock -name clock_usb -period 16.667 [get_nets {clock_usb_s}]

# The domains only meet through dual-clock stream fifos,
# synchronizers and capture registers read long after they settle, so
# paths between them carry no timing requirement.
set_clock_groups -asynchronous -group [get_clocks {clock_line}] -group [get_clocks {clock_core}] -group [get_clocks {clock_usb}]
