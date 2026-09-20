# Which clocks a GW5A pin will carry at once, and what a pin hears of itself

Two questions on one build.

The first is a placement probe: three DDR3 data pins of the fitted
site, each given the IO logic a data pin of
`nsl_ext_ram.ddr3_io.ddr3_phy_serdes` carries -- an eight wide
tristated output serialiser, a variable input delay line and an eight
wide input serialiser -- and each given its clocks from somewhere
different.  For that question the tools are the instrument and no
board is needed.

The second is the loopback below, which does need one.

The question it answers is which side of the PHY takes the quarter
period a DDR3 write needs.  On the 7-series the data pins take it: the
output serialiser runs on a fast clock shifted a quarter of a memory
period and the capture runs on the unshifted one.  If a Gowin pin
refuses that pairing, the shift has to move to the strobe, the clock
and the command pins instead, which is what `shift_strobe_c` is for.

## The three pins

|  | output serialiser | capture | parallel clock |
|---|---|---|---|
| DQ0 `one_pair_c` | 400MHz | 400MHz | 100MHz, both |
| DQ1 `shifted_output_c` | 400MHz@¼ | 400MHz | 100MHz@1/16 out, 100MHz in |
| DQ2 `divided_parallel_c` | 400MHz@¼ | 400MHz@¼ | `CLKDIV` of the unshifted 400MHz |

A constant each, because the first refusal stops the tools and takes
the other two pins with it: what is wanted is an answer per pin.  The
committed defaults build the two that pass.

## What it found

    $ gbs project build

**DQ0 and DQ2 build and route.**  One clock pair through a pin's whole
IO logic is accepted, and so is a pair whose parallel clock comes from
the pad logic's divider rather than from the PLL.

**DQ1 is refused**, by the circuit check at the end of synthesis,
before place and route is reached:

    (CK0012) Instance 'shifted_output/listener/p8.inst' has different
    control net from instance 'shifted_output/driver/p8.inst'
    connected to the same buffer 'dq_io_1_iobuf'

A pin's input and output serialisers share one control set, so they
share their clocks: a pad cannot be driven from one clock pair and
listened to on another.  This is the same refusal the earlier
`ddr3_probe2` bench met from the other direction, stated by its code.

So on this family a data pin keeps one clock pair for both directions,
and `ddr3_phy_serdes` on a Gowin part takes `shift_strobe_c => true`:
the strobe, the clock and the command pins carry the quarter period
and the data pins stay on the unshifted pair.  DQ2 says the refusal is
not about the shifted clock itself -- a pin will take it on both sides
at once.

DQ2 is only a placement answer.  The arrangement it builds is the one
`ddr3_probe2` found holding a stale word for another sixty five
nanoseconds on a board, because its serialiser's fast clock and its
parallel clock are not from the same phase; the tools have no opinion
about that and neither does this bench.

## The clock plan

The PLL request here is the one the PHY asks of this board, and the
solver is what checks it:

    Gowin PLL: refdiv=1 fbdiv=24 postdiv=1 pfd=50000kHz vco=1200000kHz
      out0=100000000Hz@port0 div=12
      out1=400000000Hz@port1 div=3
      out2=400000000Hz@port2 div=3 phase=0+1/4
      out3=100000000Hz@port3 div=12 phase=0+1/16

with `CLKOUT0_EN` through `CLKOUT3_EN` all `TRUE` in the netlist and
`CLKOUT2_PE_FINE` = `CLKOUT3_PE_FINE` = 6.  Six eighths of a 1200MHz
VCO cycle is 625ps, which is a quarter of a memory period stated once
per clock: a quarter of 400MHz's turn and a sixteenth of 100MHz's.
That the two shifts land on the same number is the check that matters
-- the pair has to move together or the strobe leaves the data behind.

An output whose rate or phase does not land on the solver's grid is
left disabled rather than approximated, so all four reading `TRUE` is
what says the plan is buildable rather than merely asked for.

## The loopback

The DDR3 bench's `ruler.py` reads the design's own write burst back off
the pins it leaves by and finds every falling-edge beat replaced by a
copy of an earlier one -- slot 1 and slot 3 holding slot 0, slot 5 and
slot 7 holding slot 4.  That reading passes through a controller, a
PHY, a part and a board.  This is the same question asked with nothing
in it: one word driven over and over out of an `OSER8`, read back at
the same pad through the `IODELAY` and the `IDES8` beside it, and
compared on chip.

Two pins are measured, on the unshifted pair both ways, which is the
arrangement `ddr3_phy_serdes` builds:

* `loop_io`, `V18`, a J6 header pin with nothing on it at all, so what
  the capture says is the pad's and not a net's;
* `dq_io[0]`, `Y4`, a DDR3 data line of the fitted site, which is the
  real case.

`dq_io[1]` and `dq_io[2]` stay placement questions and never take
their nets.

Four words are driven in turn, each stated earliest bit first: `55`
every beat, `33` every second beat, `0f` every fourth, and `17`, whose
eight rotations are all different so that a capture which is merely
turned can be told from one that has lost something.  Each is swept
over all two hundred and fifty-six taps of the line, and a line goes
out per tap at 115200 8N1 on `uart_tx_o`:

    W<driven> T<tap> P<header>/<unstable> Q<dq0>/<unstable> <locked>

A bit of the unstable mask is set when that bit was not the same at
every sample of the tap's dwell, which is how the edges of the eye say
so rather than being read as a value.  A capture equal to the driven
word, in order, at some tap is what says the pad round trip is whole.

### What it read, and why there is not more of it

One reading, and then the transport went away.  The first
configuration of this design answered:


    W33 T68 Cff U00
    W33 T69 Cff U00
    ...

-- an earlier line format, one pin, and the DDR3 pad reading all ones
at every tap it was asked about while the pad's own serialiser drove
`00110011` into it.  Nothing since has said a word.  The board still
configures (the programmer's user code readback changes with the
bitstream, and the DDR3 bench's own USB port comes back when that
bitstream is loaded), the design's report has been moved off the PLL
and back onto it, the loopback has been moved off the DDR3 net and
back onto it, and `/dev/ttyUSB` stays silent -- as does a read straight
off the FT2232's channel B endpoint with `ftdi_sio` detached.  The
FPGA runs what it is given; `U15` no longer reaches the debugger's
receiver.

So the loopback is built and unread.  What it wants is a transport
that does not go through that pin: the design's own USB2, as
`example/sipeed_tang_console_60k/ddr3` uses, or a gatecap rack over
JTAG, as the Artix bench uses.

One thing the build did say on its own, from the PnR global clock
table: `clk_i` is `V22`, whose pin function is `EMCCLK` and not a
`GCLK`, so a `clock_buffer` on it lands on long wire (`LW`) while only
the PLL's outputs take `PRIMARY` and `HCLK`.  A report clocked from the
board oscillator to survive a PLL that does not lock is a report that
does not run.  Everything here runs on a PLL output.
