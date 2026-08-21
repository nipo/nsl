// Override the internal oscillator's derived frequency so place and
// route optimizes for the application target instead of the
// evaluation board's actual clock.
create_clock -name target_clk -period 6.36 [get_pins {clk_gen/has_osca.inst/OSCOUT}]
