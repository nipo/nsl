create_clock -name clk_50 -period 20 -waveform {0 10} [get_nets {clock_buf/clock_s}]
// The host engine's domain.  Without this the tool finds an
// unconstrained clock and invents one of its own, which it sets at
// 100MHz: eight times the truth, and met only by luck.
create_clock -name usb_clk -period 20.833 -waveform {0 10.416} [get_nets {usb_clock_s}]
