create_clock -period 50.000 -name swd_clock -waveform {0.000 25.000} [get_ports swclk]

set_input_delay -clock [get_clocks swd_clock] -min 4 [get_ports -prop_thru_buffers {swdio_i}]
set_output_delay -clock [get_clocks swd_clock] -min 4 [get_ports -prop_thru_buffers {swdio_t swdio_o}]
