# Clocks are stated at the primitive pins that drive them: PLL outputs
# arrive as one vector whose scalars do not survive synthesis, while a
# primitive's output pin is a name the netlist keeps.
create_clock -name board -period 20.0 -waveform {0 10} [get_pins {clock_ext_buffer/is_global.buf/CLKOUT}]

# The memory block, as in the ddr3 example.  The two shifted outputs
# are a quarter of a memory period behind their partners; what crosses
# between a pair is two edges of one VCO, which the engine times by
# itself, so only the rate is stated.
create_clock -name mem -period 10.0 -waveform {0 5} [get_pins {ram_pll/use_plla.inst/CLKOUT0}]
create_clock -name mem_fast -period 2.5 -waveform {0 1.25} [get_pins {ram_pll/use_plla.inst/CLKOUT1}]
create_clock -name mem_data -period 2.5 -waveform {0 1.25} [get_pins {ram_pll/use_plla.inst/CLKOUT2}]
create_clock -name mem_shifted -period 10.0 -waveform {0 5} [get_pins {ram_pll/use_plla.inst/CLKOUT3}]

# 1280x720p50: 74.25 MHz pixel clock, five times that for the
# serialisers.
create_clock -name video_serial -period 2.693 -waveform {0 1.347} [get_pins {video_pll/use_plla.inst/CLKOUT0}]
create_clock -name video_pixel -period 13.468 -waveform {0 6.734} [get_pins {video_pll/use_plla.inst/CLKOUT1}]

# The sensor's pixel clock, from a pad.  It runs at 42 MHz; this
# leaves margin over it.
create_clock -name pclk -period 20.0 -waveform {0 10} [get_nets {clock_pclk_s}]

# Every crossing between these goes through a resynchroniser: the two
# stream FIFOs on each side of the memory, the frame start tick and the
# reset synchronisers.
set_clock_groups -asynchronous -group [get_clocks {mem mem_fast mem_data mem_shifted}] -group [get_clocks {video_serial video_pixel}] -group [get_clocks {pclk}] -group [get_clocks {board clk_50}]

# The memory bus, as it reaches every capture serialiser of the PHY:
# the pad carries a bus that read training places, and the delay line
# tap is a constant here.  See the ddr3 example.
set_false_path -to [get_pins {*listener/p8.inst/D}]

# The memory domain's reset release as it reaches the pads'
# serialisers, which every one of them takes asynchronously.  NSL's
# generated constraints cut this register's fabric fanout at
# `*tig_reg_clr*/CLEAR`; a Gowin primitive calls the pin RESET.
set_false_path -from [get_pins {*tig_reg_clr*/Q}] -to [get_pins {*/RESET}]
