// Override the internal oscillator's derived frequency so place and
// route optimizes for the application target instead of the
// evaluation board's actual clock.  156.25 MHz is 5G ethernet at the
// 4-byte stream width.
create_clock -name target_clk -period 6.4 [get_pins {clk_gen/has_osca.inst/OSCOUT}]
