=======================================
 DDR3 on a Tang Console 60k, by hand
=======================================

An H5TQ4G63EFR behind ``nsl_ext_ram.ddr3_io.ddr3_phy_serdes``, on a
Sipeed Tang Console 60K: two byte lanes, two strobe pairs, DDR3-800.

The same bench as ``example/xc7a50t/ddr3``, moved to a family whose
pins hold one clock pair each.  That single refusal is what the port
is about, and everything else here is the Artix bench with the data
bus twice as wide.

**The bus answers and the whole part walks clean.**  Read training
lands on the part's own multi purpose register, a burst written at the
DFI comes back whole, and every region -- the probe, the banks, the
rows, each half of the part and all 512 MiB of it -- crosses without
an error, three passes each.  The board record is in the bitstream, so
the design comes up trained with no host attached.

Two things had to be found for that, and neither was a controller.
The first was the **read offset**: this family puts a read answer at
slot **seventy** where the Artix puts it at fifty-three, and a six bit
port could not say it, so every map taken through one read a bus
nobody drove and said so.  The port carries seven bits now.

The second was **the slew rate of the pads**.  A Gowin pad defaults to
a slow output slew, which on a bus whose beat is 1.25 ns is not an
edge at all: a low beat followed by a high one came back high, a few
beats in a hundred, on three data pins out of sixteen -- and never the
other way round, which is what says an edge and not a sampling point.
Nothing in the read training sees it, because the pattern the part
answers a training read with alternates every beat and has no history
to distort.  ``SLEW_RATE=FAST`` on the data group took every region
inside a row to zero errors, and moved the read eye a beat earlier
with it.

What that took, past the two findings below, was **a memory period of
setup on the address**.  ``A14`` is the one address pin the board puts
away from the others, and half a tick was not enough for it: an
activate carrying that bit set reached the part with it clear, and a
whole-part walk lost half a percent of its beats to the collateral.
``early_address_c`` presents the address and bank on the tick before
the command as well -- the ticks a one-command-a-cycle controller
leaves deselected -- and reading 13 is what it came to.

One reading here still lies: the design's own burst, read back on the
pins it leaves by while it drives them, comes back with every odd beat
replaced by the even one before it.  That is the pad not hearing its
own driver, and it is the argument of reading 5.

The board
=========

- **GW5AT-LV60PG484AC1/I0#B**, the GW5AT-60B in a 484 ball package.
- A **50 MHz** oscillator on V22, which everything is made from.
- Two **H5TQ4G63EFR** footprints on the SOM, 4Gbit each as 256M x16.
  They share the whole command and address group -- A, BA, CS#, RAS#,
  CAS#, WE#, CKE, ODT, RESET# and CK -- and differ only in their data
  groups.  **Only the first is fitted**, which was settled by reading
  the multi purpose register through both pin groups: the first site's
  lanes answer and the second site's never move.  The board carries no
  silkscreen refdes, so that reading is the only evidence there is.
  ``../pinout/ddr3.cst`` keeps the second site's pins for the record.
- The bank runs at **1.5V** and the part takes its reference from a
  board divider: **VTTREF** reaches V3, W7, F1 and P1.  Plain LVCMOS15
  therefore carries both directions, which is what
  ``../pinout/ddr3_probe2.cst`` drove and answered on and what
  ``../pinout/ddr3_walk.cst`` follows.  SSTL15 receivers against that
  reference are a later option: a receiver threshold is worth moving
  once the bus answers at all, and not while nothing does.
- Every pin of the bus carries ``SLEW_RATE=FAST``.  A Gowin pad
  defaults to ``SLOW`` and the pin report is where that shows, since
  nothing refuses it and no simulation models it; what it costs is in
  readings 7 and 8 below.  SUG1018 §2.5 has the attribute and notes
  that the GW5A(T)-60 is one of the parts that take it.
- A15 addresses nothing at this density -- eight banks of 32768 rows
  of 1024 columns fill the 4Gbit with A0 to A14 -- and is an input of
  the part all the same, so the design holds it low rather than
  leaving it floating.

The whole part is **512 MiB**, which is four times the Artix board's.

The clock plan
==============

One PLLA makes everything from the 50 MHz oscillator, over a 1200 MHz
VCO::

  100 MHz        controller, one cycle per burst of eight   ODIV 12
  400 MHz        memory rate, unshifted: both directions
                 of every data pin, and the mask            ODIV 3
  400 MHz @ 1/4  CK, the commands and the strobe            ODIV 3, PE_FINE 6
  100 MHz @ 1/16 the parallel clock of that group           ODIV 12, PE_FINE 6

Six eighths of a VCO cycle is 625 ps, which is a quarter of a memory
period said once per clock: a quarter of the fast clock's turn and a
sixteenth of the controller clock's.  That the two shifts land on the
same number is the check that matters -- the pair has to move together
or the strobe leaves the data behind.  An output whose rate or phase
misses the solver's grid is left disabled rather than approximated, so
``CLKOUT0_EN`` through ``CLKOUT3_EN`` all reading ``TRUE`` in the
netlist is what says the plan is buildable and not merely asked for.
They do.

``example/sipeed_tang_console_60k/serdes_pin_probe`` elaborated this
plan before any of it was built into a design, and its README carries
the solver's own account of it.

Which group takes the quarter period
====================================

On the 7-series the data pins take the shift: their output serialisers
run on the quarter-shifted fast clock and their captures on the
unshifted one.  **A GW5A pin refuses that**, by the circuit check at
the end of synthesis and before place and route::

  (CK0012) Instance 'shifted_output/listener/p8.inst' has different
  control net from instance 'shifted_output/driver/p8.inst'
  connected to the same buffer 'dq_io_1_iobuf'

A pin's two serialisers share one control set, so a pad driven from
one clock pair cannot be listened to on another.  ``serdes_pin_probe``
established that with the tools rather than with a board.

So this design passes ``shift_strobe_c => true``: the strobe, CK and
every command pin carry the quarter period, and both directions of
every data pin stay on the unshifted pair.  ``DESIGN.md`` section 10
has the argument for why only the strobe's group can be the one that
crosses, and what the crossing costs -- a cycle, which the schedule
gives back everywhere except the read offset, where it shows up as a
whole word.

Three consequences follow in this design and nowhere else:

- **The strobe readback rides the shifted pair.**  The Artix bench
  reads each strobe pin back through a delay line and an input
  serialiser on the unshifted pair, beside the data.  Here the pin's
  own driver is on the shifted pair, so its listener has to be too.
  The captured word then crosses back to the controller clock in one
  register: the shifted clock's rising edge is a sixteenth of a cycle
  past the controller clock's, so a word registered there has fifteen
  sixteenths of a cycle to reach that register -- the long way round of
  the pair, and the only direction this bench crosses in.
- **That crossing costs the readback a cycle** the PHY's own data path
  does not pay, and the strobe's group pays one going out.  So what
  the two words say about each other would be a reading and not a
  calibration, and ``ruler.py`` is what times them together.  On the
  board that reading is not to be had on a write: a pad hears nothing
  of its own driver at the beat rate, which is in "What is open"
  below, and the strobe's word alternates every beat.  On a read it
  is, and the strobe reads as a clean alternation there.
- **Each strobe is a pair of ordinary pins**, driven complementary from
  two tristated serialisers, rather than a differential primitive: the
  bank runs LVCMOS15.  That is what ``ddr3_probe2`` drove, and the PHY
  hands both halves over separately for exactly this case.

The design
==========

Everything above the pins is the library, as on the Artix:
``dram_core`` above the DFI line, ``axi4_mm_burst_adapter`` above
that, and four ``axi4_mm_memory_tester`` walkers.  The four regions
are read off the core's own address map rather than picked -- an
access carries sixteen bytes, so address bits 4 to 10 are the column,
11 to 13 the bank and 14 up the row::

  size 0   256 bytes    sixteen accesses inside one page, for the maps
  size 1   512 MiB      the whole part
  size 2   16 KiB       every bank at row zero: seven bank crossings,
                        no row change, nothing precharged
  size 3   32 KiB       the first row crossing on top of that

A page is two kilobytes, the bank turns over every two of them and the
row every sixteen, so a contiguous region cannot reach a second row
without having crossed every bank boundary first.  That is the whole
of the ladder the address map offers, and it is what separated the two
faults of reading 8: the small regions exercise fourteen address bits
and the whole part exercises twenty-nine, so a weak line high up the
row address shows on one and not the others.

The rack rides the board's **own USB2 port**, which the fabric drives
through the soft high-speed PHY kept in the gatecap tree: the design
appears as a serial port and ``nsl_bnoc.chunked_link`` carries the
rack over it.  The Artix bench reaches its rack over JTAG instead;
nothing else about the rack differs.  A consequence worth stating: the
port only exists while a design driving it is loaded, so there is no
way to reach the panel of a board that is not programmed.

``clocks.sdc`` says what is and is not constrained, and why each clock
is stated at the pin that drives it rather than at a net the design
names: the four outputs of one block arrive as one vector and the
scalar each is read out of does not survive synthesis.

The settings
============

What this board is to measure of the PHY is one constant in
``src/boundary.vhd``, handed to ``ddr3_phy_serdes`` as its ``board_c``
generic::

  constant board_c: nsl_ext_ram.ddr3_io.serdes_board_t := (
    read_offset => 70,
    read_tap => 47,
    write_slip => 7,
    dq_enable_lead => 0,
    dqs_enable_lead => 0,
    strobe_invert => false
    );

Three of the six are what the family says rather than what the board
says, and were known before a measurement:

- both **enable leads are zero**.  A GW5A pad's tristate is per pair
  and travels with the word its own serialiser presents.
- ``strobe_invert`` is **false**, which is the sense the schedule
  holds.

The other three are measured, and all three are off the nominal:

- ``read_offset`` is **70**, against the Artix's 53.  A whole cycle of
  that is the output stage both families gained; the rest is the
  strobe's group crossing to the shifted pair, which a 7-series pin
  does not do.  The port had six bits when this board was first mapped
  and could not say seventy at all, which is why every map before this
  one was empty.  It read 71 while the pads were at the family's
  default slew, and a faster edge arrives a beat earlier.
- ``read_tap`` is **47**, the middle of the run of 41 taps over which
  a walk of the array is clean.  The part's own training pattern
  answers over a wider run at a different centre, 73 taps centred on
  52, because it alternates every beat and so is the easiest traffic
  there is; the record follows the array.  The offset either side of
  this one answers over a run of its own, eighty-odd taps away: the
  line carries 256 taps of about 12.5 ps and a beat is 1.25 ns, so the
  runs are one window reached a beat apart.
- ``write_slip`` is **7**, a slot short of nominal.  There is no
  whole-word transfer for the data to lose here -- a real ``OSER8``
  takes its parallel word on a parallel edge, unlike the 7-series,
  whose data serialiser hands its word a cycle early and wants slip 0
  -- so eight was the expectation.  The remaining slot is the strobe's
  own crossing arriving a beat ahead of the data it clocks.  At eight
  the part drops the first beat of every burst and stores the other
  seven; at six it drops the last; at seven the burst comes back
  whole.

One thing this board asks of the PHY is not in the record, and is a
generic beside it: ``early_address_c => true``.  A command belongs to
one memory tick and CK rises in its middle, so an address pin is
settled half a tick either side of the edge that reads it -- 1.25 ns
here, and not enough for ``A14`` at D1.  With the generic on, a tick
that deselects the part carries the address and bank of the tick
*after* it rather than its own, so a command following a deselect is
presented a tick and a half early.  Only the address and the bank
move: CS, RAS, CAS and WE stay on their own tick, or the deselect
would reach the part as a second command.  ``dram_core`` writes
``dfi_o.command(0)`` alone and leaves the other three phases
deselected, so the three ticks behind every command are free.  It is a
generic and not a seventh field of ``serdes_board_t`` because that
record is an aggregate every board states in full, and a field added
to it rewrites every board.

The PHY applies the record itself: out of reset it waits for the delay
reference, walks every data pin's line round to its mark and then out
to ``read_tap``, and only then raises ``init_complete``.  On this
family the reference has nothing to lock to -- ``IODELAY`` takes its
tap as a number and applies it -- so ``delay_reference`` is a wire
that says ready as soon as it is out of reset, and the clock the PHY
is handed for it reaches nothing.

What the build says
===================

``gbs project build``, with the Gowin flow.

The clock plan comes out of the solver as asked: ``IDIV_SEL`` 1,
``FBDIV_SEL`` 1, ``MDIV_SEL`` 24 for a 1200 MHz VCO, ``ODIV0_SEL`` 12,
``ODIV1_SEL`` 3, ``ODIV2_SEL`` 3, ``ODIV3_SEL`` 12, and
``CLKOUT2_PE_FINE`` = ``CLKOUT3_PE_FINE`` = 6 with all four outputs
enabled.

It costs, of a GW5AT-60::

  logic       15969/59904   27%   (13943 LUT, 1456 ALU, 570 ROM16)
  register    14004/60780   24%
  CLS         14558/29952   49%
  IOLOGIC        70/293     24%   47 OSER8, 20 IDES8, 18 IODELAY
  BSRAM          22/118     19%
  I/O port       58/297     20%

Eighteen delay lines is sixteen data pins and two strobes; the two
extra input serialisers over the eighteen readbacks belong to the soft
USB PHY.

What the flow objected to, and how it was answered:

- **A clock cannot be stated at a net this design names.**  The four
  PLL outputs arrive as one vector and the scalar each is read out of
  is optimised away, so ``create_clock ... [get_nets {ram_s}]`` is
  refused outright with ``(TA2003) Can't set timing constraint to
  object ram_s`` and the build stops before placement.  Every clock in
  ``clocks.sdc`` is therefore stated at the pin that drives it --
  ``ram_pll/use_plla.inst/CLKOUT0`` and its three siblings, the
  buffered board clock at ``board_buffer/is_global.buf/CLKOUT`` and
  the transport's at
  ``usb_pll/has_pll.inst/use_plla.inst/CLKOUT0`` -- which are names
  the netlist keeps.  The tool derives a clock at each of those pins
  by itself and puts a default rate on it; what the file does is give
  it the rate the design was built for.
- **Gowin's SDC parser takes no line continuation.**  A
  ``set_clock_groups`` split over several lines with a trailing
  backslash is a syntax error, ``(TA2000) 'syntax error' near token
  '\'``.  It goes on one line.
- **Two things the engine timed that are not paths**, each of which
  dominated the report until it was cut, and each cut in
  ``clocks.sdc`` with its reason:

  - **the delay line's tap value into the pin's own capture.**  The tap
    register sits in the controller domain, the ``IODELAY`` it feeds
    adds most of a nanosecond, and the input serialiser behind it
    samples at 400 MHz: 4.0 ns of negative slack on every data pin, and
    the whole of the memory domain's report.  A 7-series ``IDELAYE2``
    takes ``CE`` and ``INC`` pulses in the capture's own domain and has
    no such path, so this appears on porting and nowhere before it.
  - **the memory domain's reset into the pads' serialisers**, 2.2 ns.
    NSL's generated constraints cut this register's fanout at
    ``*tig_reg_clr*/CLEAR``, which covers fabric registers; a Gowin
    primitive calls the same pin ``RESET`` and escapes the rule.

  **The panel's whole-slot knobs were a third**, at 11.6 ns against a
  controller cycle of 10: the PHY read the slip, the leads, the offset
  and the strobe's sense combinationally into every serialiser's word,
  so a knob that moved crossed the die from the rack and then a sixteen
  way mux per bit of every pin.  ``ddr3_phy_serdes`` samples all five
  at its own input now and reads that register everywhere below, which
  takes the die crossing out and leaves the mux: 10.3 ns, still short
  of 10.  What settled it is the PHY's **output stage**: every pad
  takes its word, and its enable with it, from a register of its own,
  so the mux and the widening of a drive bit into an enable word have
  a whole cycle and the pads' own net carries routing and nothing
  else.  The slip still reaches 658 loads over 3.4 ns; it now does so
  with 1.85 ns of slack.  The stage costs one cycle on both families
  and ``read_offset`` grows by a word with it (``DESIGN.md`` §10).

The build the readings below come off reads::

  board          50.000 MHz constraint   175.133 MHz actual   met
  mem           100.000 MHz constraint    92.280 MHz actual   short
  mem_shifted   100.000 MHz constraint   269.736 MHz actual   met
  usb            60.002 MHz constraint    69.045 MHz actual   met
  290 setup endpoints violated, TNS -81.316 ns; 13 hold

Every one of the 290 is a family this report has always carried and
none of them is the command path: the burst adapter's transaction
address into a walker's hash at -0.837 ns worst, the panel's walker
selector into the core's write data enables, and the core's own
scheduler.  The board is what says whether it costs anything, and with
this build it walks the whole part clean three times.  Builds of this
bench have read between 86.2 and 100.5 MHz on ``mem`` with the failing
paths in that handful of families; a tenth of a nanosecond here is the
placer's.

Getting there took two placer options, one constraint and two register
stages.

**Two walkers more cost it.**  The build the halves of reading 10 come
out of reads 88.928 MHz on ``mem``, TNS -75.689 ns over 257 endpoints
and nothing violated anywhere else, which is the spread this design's
placements have always had rather than anything new.  Every one of the
257 is the bench's own: the burst adapter's transaction address
reaching a walker's hash, which is the family that has been at the top
of this report since there were four walkers, with six of them on one
bus to fan out into.  The board is what says whether it costs
anything, and it says region 4 walks 16777216 beats clean while region
5 does not, so what the report has is distance and not an error.

**The tool routes a bench's enables on the global clock tree.**  A
GW5AT-60 has eight *primary* global clock resources and eight *long
wires*, and the placer hands them to whatever net it thinks wants them
-- fanout being the whole of the argument.  ``axi4_mm_memory_tester``
advances its hash pipeline on one enable, so a walker's
``transition.advance`` carries 189 to 334 clock enables; the four
walkers' resets carry 261 to 442 more.  With eight such nets in a
design that has eight real clocks, the budget goes to the bench::

  raw_s[0]                     PRIMARY   the controller clock, 8393 loads
  raw_s_422[3]                 PRIMARY   the shifted controller clock
  hs_phy/.../sclk              PRIMARY   the soft PHY's own
  probe/n483_5                 PRIMARY   the probe walker's reset, 261
  bank_walk/n488_5             PRIMARY   that walker's reset, 272
  row_walk/n489_5              PRIMARY   that walker's reset, 279
  walk/transition.advance      PRIMARY   a beat enable, 334 clock enables
  bank_walk/transition.advance PRIMARY   a beat enable, 193
  board_s, ram_reset_n_s, utmi clock, the memory domain's own reset,
  mem_fast, mem_data, walk/n503_7 (a reset, 442), hs_phy/fast_clock_s
                               LW        eight of eight

Eight of eight primary, and two of them spent on enables.  That is the
build that read **88.609 MHz on** ``mem``, TNS -226.061 ns over 577
endpoints, with ``usb`` 1.9 MHz short as well: nothing in the
controller reaches those two nets, and the whole device placed worse
for them.

**The lever is** ``CLOCK_LOC ... LOCAL_CLOCK``, in the pinout rather
than the SDC.  SUG1018 *Arora V Design Physical Constraints User
Guide* §2.7 defines it -- "LOCAL_CLOCK means this net is not routed to
the global clock wire", and with ``LOCAL_CLOCK`` no ``signal_type`` is
taken -- and SUG113 *Gowin FPGA Design User Guide* §4.3.2 prescribes
exactly this when the clock resources are exceeded.  GowinSynthesis
offers no counterpart: SUG550 lists ``syn_maxfan`` and nothing that
says *not a clock*, because the promotion is the placer's and not the
synthesiser's.  ``../pinout/ddr3_walk.cst`` names all four walkers,
not the two a given build promotes::

  CLOCK_LOC "probe/transition.advance" LOCAL_CLOCK;
  CLOCK_LOC "walk/transition.advance" LOCAL_CLOCK;
  CLOCK_LOC "bank_walk/transition.advance" LOCAL_CLOCK;
  CLOCK_LOC "row_walk/transition.advance" LOCAL_CLOCK;

Which walker wins a primary is the placer's; what the net *is* belongs
to the design.  The walkers' resets are not nameable -- each comes out
of synthesis as ``nNNN_5`` -- and they are set/reset nets, which is
what the resource is for, so they are left alone.  On its own the
constraint took ``mem`` to 89.466 MHz and TNS to -44.614 ns over 90
endpoints, and gave ``usb`` all but one endpoint back: a sixth of the
negative slack survived, and it was all distance.

**What names cannot reach, two placer options can.**  A build of the
record alone -- three constants moved, nothing else -- placed at
86.237 MHz on ``mem`` and 55.376 MHz on ``usb``, and on the board its
own rack answered with a corrupt descriptor and a controller clock
read as 4 MHz, 120 MHz and 200 MHz on three consecutive tries.  The
netlist had barely moved and the device had been re-placed around it,
which is the failure mode the global-clock policy was meant to end and
only half did: three walker resets held primaries and the 400 MHz
pair sat on long wires.  ``project.gbs.yaml`` therefore asks for two
things the tool does not do by default::

  replicate_resources: 1      # SUG1220: split a high-fanout driver
  place_option: 3             # Gowin's own default on the larger Arora V

Replication takes the argument for promoting a bench's reset away by
making it several smaller nets.  Together they gave 98.787 MHz on
``mem``, ``usb`` met with no violated endpoint at all, one primary
left spare, and -- with the pads' slew rate the only change between
two builds -- an identical placement twice running, which is the first
time a reading of this design has repeated.

**Two register stages spent that distance.**  Both are the bench
reaching across the die, and both cost a cycle of a thing no cycle
depends on:

- **the panel's walker selector.**  ``full_s`` comes out of a
  resynchroniser that lives with the rack at the east edge, and it
  releases one walker's reset and picks one of four masters for the
  adapter -- logic that sits with the controller, half the die west.
  ``full_r_s`` registers it in the memory domain, so the rack's
  distance and the mux each get a cycle.  Which walker runs changes
  only between runs.
- **the DFI command counters.**  The counters are instruments and sit
  with the panel; what crossed to them was the decode of the command
  the core had just issued, arriving as the enable of a thirty-two bit
  counter.  ``count_step_s`` is that decode registered beside the
  controller, one bit per kind, and the counters follow it.  The
  totals stand a cycle behind the bus and are read by a host.

Two earlier stages of the same kind are still there and still worth
knowing, since both change when a reading lands rather than what it
says:

- **the capture's whole word** goes through one register stage, the
  two trigger sources with it, so neither the analyser's memory nor
  its trigger enable is reached through the sequencer's mux over the
  DFI, the reduction of a walker's 32 bit error count to a bit, or the
  adapter's address arithmetic behind both.  Every field moves
  together, so a window holds the same samples in the same order and
  the recording sits one cycle later in absolute time.
- **the strobe window's read-out slot** comes off a register of its
  own rather than from the panel's offset across the die.  The index
  is not data: the pipeline is the same depth and all that moves is
  when a new offset begins to apply, a cycle later.

What that leaves is **nothing negative**.  The tightest paths in the
report are the rack's own APB bridge at +0.003 ns and the burst
adapter's transaction address reaching a walker's hash at +0.047::

  +0.003  the rack's APB bridge, address into its word register
  +0.047  adapter/r.txn.addr -> read_stage/slice/r.data/RESET
  +0.048  adapter/r.txn.addr -> probe/r.stirred[2][1]/CE

The families this file used to list -- the panel's counters off
``core/r.step``, the panel's control into ``core/r.acc_address``, the
walkers' comparison a nanosecond out -- are gone from the report
entirely.  Earlier builds left a handful of the adapter's endpoints a
tenth of a nanosecond short and that was always the placer's noise
rather than a path: what was failing on the board at the time was the
pads, which are readings 7 and 8.

All **thirteen hold** violations are inside the vendor's soft
high-speed PHY, between its 60 MHz side and the 120 MHz side its own
``CLKDIV`` makes, on gray-coded FIFO pointers, as the fourteen before
them were.  ``ddr3_probe2`` shipped with them unanalysed -- it states
no clock for that domain -- and worked on this board.

What neither the constraint nor the options did is empty the
primaries: the tool promotes whatever is left, and this build spends
four of eight on walker resets and one on a core state bit.  The
400 MHz pair sits on long wires and on hard clock rows, which is where
it belongs::

  raw_s[0], raw_s_395[3]           PRIMARY  the two controller clocks
  hs_phy/.../sclk                  PRIMARY  the soft PHY's own
  core/gowin_reg_r.state_400[6]_1  PRIMARY  a core state bit
  walk/n503_7, bank_walk/n488_8,
  row_walk/n489_7, low_walk/n502_7 PRIMARY  four walker resets
  board_s, ram_reset_n_s, utmi clock, n451_7,
  raw_s_393[1], raw_s_394[2], high_walk/n502_7,
  hs_phy/fast_clock_s              LW       eight of eight

  raw_s_393[1]                     HCLK     BANK9_HCLK1
  raw_s_394[2]                     HCLK     BANK9_HCLK2 BANK10_BANK11_HCLK3

One thing to know before reading any of these numbers twice: the
tool's placement of this design used to move with the size of the
changes above.  Builds of it have read 98.935, 95.180, 93.671, 93.480,
88.609, 89.466, 99.623, 86.237, 98.787, 100.468 and now 92.280 MHz on
``mem`` while the failing paths stayed in a handful of families, and
``board`` moved between 123 and 190 MHz and ``mem_shifted`` between
121 and 270 without either being touched.  At 49% of the part's CLS
and with a clock of 8393 loads, a tenth of a nanosecond of worst slack
here is the placer's, and the board is what says what it costs.

What the ladder said
====================

Every reading below comes off the committed bitstream, over the rack
on the board's own USB2 port.  That bitstream carries the board record
out of ``src/boundary.vhd``, so nothing below touches the panel's
``manual`` bit except where it says so: the PHY places itself at reset
and a walk measures the record the design was built with.

**1. The transport and the clock.**  The rack enumerates and lists its
blocks -- the bridge, the enumerator, the clock measurer, the panel,
the register file, the capture and the DFI analyzer's three -- and the
measurer reads the controller clock at exactly what the design was
built for::

  clock,rate_hz
  ram,100000000

Every resolve over this port hangs before printing anything until the
port is put in raw mode, whatever verb asks for it; ``stty -F
/dev/ttyACM0 raw -echo`` after programming is what makes any of the
readings below possible.

**2. The panel, before any walk.**  Straight after configuration, and
unchanged two seconds later::

  ready                  1
  error_count            0
  act_count              0
  pre_count              1
  ref_count              2
  mrs_count              4
  handshake              0

Which is the Artix's reading exactly: the power-up script has played
once and nothing else has.  The refreshes stop at two because the run
bit holds the core in reset and that is where it is.  Every control
register reads **zero** after configuration, as on the Artix and not
as on the Lattice board the SDRAM bench runs on, so ``walk.py``
raising the run before it drops it costs nothing here rather than
being what makes the drop a transition.

**3. The read map lands, once the offset can reach it.**  ``mpr.py``
maps every offset the port carries against the line.  Over the
sixty-four a six bit port could say it finds nothing at all -- which
is what this file used to record, and what sent the whole
investigation after the capture.  Over a hundred and twenty-eight it
finds the answer::

  offsets that answered coarsely: (69, 70, 71, 72)
    offset 69: 3 taps, taps 0 to 2
    offset 70: 73 taps, taps 16 to 88
    offset 71: 71 taps, taps 101 to 171
    offset 72: 70 taps, taps 186 to 255
  the part's pattern comes back at read offset 70, over 73 taps of the
  line; the middle of that run is tap 52

Three offsets answer over runs of their own, eighty-odd taps apart:
one window reached a beat early, on the beat, and a beat late.  A
window of 73 taps is 0.9 ns of a 1.25 ns beat, so the read path is not
merely found but wide.  It is not as wide as it looks, which is
reading 9.

The instrument was never what was broken.  The panel's tick moves the
delay lines and they wrap where the family says they should::

  delay_mark over 12 ticks from rest: 0xffff 0x0000 0x0000 ... 0x0000
  ticks from rest back to the mark: 256

**4. The part is alive and the strobe reaches it.**  ``level.py`` puts
the part in write levelling, where it drives its data lines with what
it sampled of CK on each rising strobe edge::

  --- termination on
    not levelling:  0x0000
    levelling:      0xff00
    the answer sits at 0xff00: the part has taken the bus, so the strobe reaches it
  --- termination off
    not levelling:  0x0000
    levelling:      0xffff  (moving)
    the answer sits at 0xffff: the part has taken the bus, so the strobe reaches it

So the command pins are decoded, a mode register write lands and the
part drives sixteen data pins.  Two lanes answering differently and an
answer that moves between two readings are what sampling looks like: a
flop nobody clocked would read the same on both lanes and stay there.
What the reading does not prove on its own is that the strobe carries
a *beat rate* -- one rising edge in a burst is enough to update the
part's feedback flop -- and reading 3 is what settles that, since a
part answering an MPR read has taken the READ command, the MPR entry
and the burst.

The same passes say the strobe pin reads back flat -- ``ever high
0x00, ever low 0xff`` on both lanes -- while its own driver drives.
That is the loopback of reading 5 again, on the pin whose word
alternates every beat: the same readback resolves the *part's* strobe
perfectly, as ``01010101`` and ``10101010`` at the offsets the read
answer sits at.

**5. What the design's own burst says, and why it says it twice.**
``ruler.py`` announces the capture on the cycle of a *write*, so the
pads' own receivers see the burst the design is driving.  With the
poke counting up from ``0x40``, lane 0 of slot *s* should read
``0x40 + 2s``.  At the trained tap and offset it reads::

  slot   0     1     2     3     4     5     6     7
  want   40    42    44    46    48    4a    4c    4e
  got    40    40    44    44    48    48    4c    4c

**Every odd beat is a copy of the even one before it**, and that
holds at every one of the 256 taps of the line and at every slip.  The
tempting reading is that the capture drops a beat; it is wrong, and
three measurements say so.

- **The line cannot undo it.**  A capture whose falling-edge half were
  dead would show the odd beats once the line moved the sampling point
  a beat, since the line spans some three of them.  It never does: the
  window walks a slot later per eighty-odd taps, monotonically, and
  the shape of the word never changes.
- **The slip cannot undo it either.**  A pad emitting only the even
  positions of the word it is given would turn the odd beats up at an
  odd slip.  Slips 6 to 10 move the burst a slot a step and leave the
  shape exactly as it is, so what is duplicated follows the burst and
  not the serialiser's word.
- **The part sees the beats the loopback does not.**  A burst written
  at the DFI and read back out of the array comes back ``40 41 42 43
  44 45 46 47 48 49 4a 4b 4c 4d 4e 4f`` -- whole, odd beats included.
  The part's receivers resolve what this design's own receivers, on
  the same pins, do not.

So the loss is neither the drive nor the capture of anything the bus
carries: it is a **pad listening to itself while it drives**.  The
receiver of a GW5A pad does not resolve a 1.25 ns beat out of its own
driver's waveform, and does resolve one out of the part's -- the MPR
answer in reading 3 alternates every beat and comes back whole through
the same pad, the same ``IODELAY`` and the same ``IDES8``.  Turning
the part's termination off makes the loopback worse rather than
better, which is what a settling time does and not what a dropped beat
does.

``ruler.py``, ``taps.py`` and ``drivemap.py`` all read the bus this
way, so none of them measures what it means to.  The slip is measured
against the array instead, in reading 6.

**6. The poke lands, and places the slip.**  A burst written at the
DFI and read back from the array, at the read point of the day --
offset 71 and tap 107, before the slew was set::

  slip 6   40 41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4c 4d
  slip 7   40 41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f
  slip 8   00 00 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f

A slot either side of seven loses an end beat, and seven is whole.
That is the whole of write training this bench needs, and it is
measured against the part rather than against a pin.  The slip is a
whole beat and the slew moved the timing by a third of one, so it did
not move; what says so is a clean walk, which is a write landing
1024 times over.

**7. What a bad beat was, before the slew was set.**  A build of the
record with every pad at the family's default slew walked the probe's
region clean and missed beats everywhere else::

  region 0   256 bytes          16 accesses       0 errors
  region 2   16 KiB, every bank  1024 beats     155 errors
  region 3   32 KiB, two rows    2048 beats     174 errors
  region 1   512 MiB         33554432 beats 1522528 errors, 1.65 s

The shape of it said what it was, and none of the three things the
counts suggested was right.

- **It was not the cadence.**  ``first_error_address`` reads ``0x170``
  on five walks of region 2 out of six, which is inside the *first*
  page of the region, so nothing has crossed a bank or a row when it
  fails.  ``trace.py size=2`` catches the failing cycle with the
  thousand before it: the bad beat is the twenty-fourth read of a
  string of reads of one open row, with the nearest refresh 250 cycles
  behind it and no activate or precharge between.
- **It was not the controller.**  The same window carries 522 write
  bursts with their bank and column, and every one of them puts the
  payload the walker's own hash says that address should hold on the
  DFI.  What leaves the controller is right; what comes back is not.
- **It was not the sampling point.**  ``dataeye.py`` walks the whole
  of region 2 at every tap of the line.  The window is taps 72 to 132,
  which is the one ``mpr.py`` maps, and inside it the count never
  falls below 139 and never rises above 190.  A floor that flat across
  sixty taps is not an eye edge.

What it was is in the beats themselves.  Paired against the walker's
own hash, 204 of 960 read bursts came back wrong and carried 233 bad
bits between them -- about one bit a burst -- and every one of the 233
had the same shape::

  the bad bit is a zero, and the next beat of the same pin is a one   229 / 233
  the bad bit read one where zero was written                         233 / 233
  the bad bit read zero where one was written                           0 / 233

  DQ1   7.2% of its zeroes that are followed by a one
  DQ12  4.6%
  DQ7   1.1%
  the other thirteen pins        0.0%, over 1400 to 2900 chances each

A high that reaches backwards into the low before it, on three pins
and never the reverse, is a pad whose rising edge is early against its
falling one -- an edge, not a threshold and not a phase.  The pin
report says why: **every pad of the bus was at** ``slew SLOW``, which
is the family's default and which nothing in the flow, the netlist or
any simulation mentions.  A slow edge on a 1.25 ns beat is most of the
beat.  The part's own training pattern never showed it because it
alternates every beat and so has no run of history to distort.

**8. With** ``SLEW_RATE=FAST`` **on the bus**, and the board record at
what reading 9 measures.  Out of the bitstream, nothing on the panel
touched::

  region 0   256 bytes          16 accesses      0 errors, 3 walks
  region 2   16 KiB, every bank  1024 beats      0 errors, 3 walks
  region 3   32 KiB, two rows    2048 beats      0 errors, 3 walks
  region 1   512 MiB         33554432 beats 206962, 253383, 267502

Every region that stays inside a row is clean, three walks each, and
the whole part is six times better than it was.  What is left has a
different shape entirely:
whole bursts wrong rather than single bits, in runs of forty or a
hundred, and each one carrying a real payload -- the payload of the
**same bank and same column of the row with bit 14 set**, read while
the pins said bit 14 clear.  Over one window, 128 of 296 paired read
bursts, and every one of the 128 the same::

  the payload of this address with row bit 14 set      128 / 128
  the payload of this address with row bit 14 cleared    0 / 128
  the payload of any other row, or of another bank       0 / 128

That is **A14**, and reading 10 says which way round: the pins did say
bit 14 clear on that read and the read was right, what was wrong was
the write of the address with the bit *set*, which landed with it
clear.  It is the one address pin the board puts away from the others
-- D1, where the other fourteen sit in the G to R block beside CK at
L3 -- and a fast slew on the command group does not move it::

  region 1   512 MiB    33554432 beats   186483 errors  data group fast
  region 1   512 MiB    33554432 beats   153693 errors  command group too

**9. The read eye moves with the slew, and the array's eye is not the
part's.**  With the bus fast, ``mpr.py`` finds the part's pattern at
offset **70** over 73 taps, 16 to 88; it was offset 71 over taps 71 to
143 before.  A faster edge arrives earlier, by about thirty taps of
12.5 ps, and a whole beat of offset with it.  But ``dataeye.py`` walks
region 2 at every tap and reads a *narrower* window at a *different*
centre::

  offset 70, the part's own pattern    73 taps, 16 to 88, centre 52
  offset 70, 1024 beats of the array   41 taps, 27 to 67, centre 47

Forty-one taps that reach **zero errors**, which no tap of any
previous build did.  Training against something the part made owes
nothing to a write and is the right thing to do first; it is not the
last thing to do, because the traffic a design carries is harder than
an alternation and draws a smaller eye.  The board record is the
middle of the second one.

**10. Which half of the part.**  Two more walkers, which differ in the
top row bit alone: region 4 addresses every bank, row and column of
the part with A14 held **low** throughout, region 5 does the same with
it held **high**, and neither ever changes it.  Out of the bitstream,
nothing on the panel touched::

  region 4   256 MiB, A14 low   16777216 beats       0,   0,   1
  region 5   256 MiB, A14 high  16777216 beats    2694, 439, 1205
  region 1   512 MiB            33554432 beats   44307, 13930, 32250

The lower half's one bad beat is not noise: it is byte ``0xe5cc810``
every time it appears, which is bank 1 of row ``0x3973``, and reading
12 finds the same one beat at the middle of the read window.  One
location in sixteen million, at the same place, is either a cell of
the part or the one path this build leaves short -- the burst
adapter's transaction address into that walker's hash, which is where
its 257 endpoints are.  It is three orders of magnitude below what the
upper half does and is left alone.

Everything above is unchanged on this build: ``mpr.py`` finds the
part's pattern at offset 70 over 72 taps, 17 to 88, with the middle at
52, ``poke.py``'s answer follows its value either way of the TDQS bit,
and regions 0, 2 and 3 walk clean three times each.

The lower half is clean and the upper half is not, so what a
whole-part walk fails on is that one pin and nothing else: not the
other fourteen row bits, not the three bank bits, not the column, and
not the data path, every bit of which the lower half exercises over
the same sixteen million beats.

It also settles the direction, which reading 8 has the wrong way
round.  The lower half never drives A14 high, so a pin read high where
low was driven would fail there, and it does not.  What a whole-part
walk sees is the collateral of the other direction: the write of the
address with row bit 14 **set** lands with it **clear**, overwriting
the low address, whose own read is then right about a location that
now holds the high address's payload.  **A14 is driven high and
sampled low**, on the activate that carries it; the column commands
that follow an activate do not care what that pin says.

**11. The margin is near zero, and no number the design carries sets
it.**  Region 5 at the board record, over three configurations of one
bitstream and three passes of each::

  configuration 1                                 2694,  439, 1205
  configuration 2                                51935, 2455, 4723
  configuration 3                                  315,  881,  887

  the build of reading 8, one pass                        242586

An order of magnitude between passes that share a configuration and
another between one bitstream's configurations: the part samples that
pin on the edge of its window, and which side of it a given activate
falls is decided by the conditions of the hour.  The build of reading
8 is two hundred times worse again, and the two builds differ by two
walkers and a placement -- so the size of the fault is the build's,
and having one at all is the pin's.

A longer memory period does not buy the margin back.  A build at
**81.25 MHz** -- ``tck_ps_c`` 3077, a 1300 MHz VCO with divisors 16,
4, 4, 16, and the quarter period a whole VCO cycle rather than six
eighths of one -- trained at its own read offset and walked the same
three regions to the same answer: lower half clean, upper half 300908,
whole part 135630.  A quarter of a nanosecond more window either side
of the sampling edge changed nothing, which a fixed pad-to-pad skew
would have spent.

**12. No tap of the delay line takes it away.**  ``dataeye.py`` walks
a region at every tap and counts, which is the read plane drawn with
the traffic a design carries rather than with the part's own pattern.
The two halves draw the same window and different floors, one walk a
tap, sixteen taps a step::

  tap      region 4, A14 low   region 5, A14 high
  0                 16777216            16777216
  16                16227236            16280104
  32                      77                2156
  48                       1                2351
  64                    2187                4457
  80                14219831            14034685
  96 and up         16777216            16777216

The window is the same one either way -- taps 32 to 64 of 256 -- so
the read path does not know which half of the part it is reading.
What differs is what the bottom of that window holds: one bad beat in
sixteen million for the lower half, two thousand for the upper, and
no tap anywhere on the line that takes the difference away.  A beat
the capture got wrong moves with the tap; this does not, so it is not
in the capture, and the walk of the lower half says the same thing
about every other pin on the bus.

**13. The address a tick early closes it.**  ``early_address_c =>
true`` in ``src/boundary.vhd``, nothing else moved.  Out of the
bitstream, nothing on the panel touched::

  region 0   256 bytes              16 accesses     0, 0, 0
  region 2   16 KiB, every bank     1024 beats      0, 0, 0
  region 3   32 KiB, two rows       2048 beats      0, 0, 0
  region 5   256 MiB, A14 high  16777216 beats      0, 0, 0
  region 4   256 MiB, A14 low   16777216 beats      1, 0, 0
  region 1   512 MiB            33554432 beats      0, 0, 0

**Region 5 is the reading.**  The half of the part that drives A14
high on every activate failed in under a second on every build before
this one -- 315 to 51935 bad beats a pass, over three configurations
of one bitstream and the build of reading 8 two hundred times worse
again -- and it now walks sixteen million beats clean, three passes.
The whole part follows: 33554432 beats, three passes, no error, where
the best previous build lost 13930.

Everything else reads as it did.  ``mpr.py`` finds the part's pattern
over the same four offsets and the same runs -- 69 for three taps, 70
over 72 taps from 16, 71 over 73 from 99, 72 over 72 from 184 -- so
the read path did not move; the record's tap sits in the run at 16 to
87 as it did.  ``poke.py``'s answer follows its value either way of
the TDQS bit.  The lower half's one bad beat is still byte
``0xe5cc810``, on one pass of three, which is reading 10's and is not
A14.

The margin the command pins had was half a memory tick and is now a
tick and a half.  That is the whole of the change: no pin attribute,
no clock rate, no placement and no tap.

What is open
============

- **A14 was driven high and sampled low** on an activate, and reading
  13 closed it.  Readings 10 and 11 had the isolation -- the half of
  the part that never drives that pin high walked clean over sixteen
  million beats, the half that drives it high on every activate did
  not, and the DFI analyser saw the right row leave the controller
  either way -- and none of the pad's own knobs moved it: the pin
  report carries ``SLEW_RATE=FAST`` at D1 as at the other fifteen
  address pins, ``DRIVE=16`` is refused outright on an LVCMOS15 pad of
  this part with ``(CT1108) Illegal port attribute value specified``,
  a build at 81.25 MHz read the same, and no tap of the delay line
  took it away.  What it wanted was setup, and this family has no
  output delay line to buy any with.  ``early_address_c`` buys it out
  of the schedule instead: the three ticks a one-command-a-cycle
  controller leaves deselected carry no address the part reads, so the
  address of the tick after a deselect goes out on it.  What is left
  to know is how much margin that bought rather than whether it
  bought enough -- a pin whose skew is a tick and a half would come
  back, and there is no instrument here that measures it.
- **A pad's slew rate is a setting with no default worth having, and
  nothing says so.**  ``SLOW`` is what a GW5A pad takes if a design
  does not ask, the flow raises no message, the netlist does not carry
  it and no simulation of this bench models a pad's edge at all.  It
  is visible in exactly one place, the pin report's *Slew Rate*
  column, which is not a place anyone reads while chasing a
  controller.  Readings 7 and 8 are what it cost here.
- **A GW5A pad does not hear its own driver at the beat rate.**  Every
  self-loopback instrument here -- ``ruler.py``, ``taps.py``,
  ``drivemap.py`` -- reads the design's own burst with each odd beat
  replaced by the even one before it, at every tap and every slip,
  while the same pad, the same ``IODELAY`` and the same ``IDES8``
  resolve the part's own alternating pattern perfectly.  Reading 5 has
  the three measurements that separate the two.  It survived the slew
  rate, so it is not the edge that reading 7 was: the DQ pins carry no
  ``DRIVE`` attribute in ``../pinout/ddr3_walk.cst``, where the clock
  pins carry ``DRIVE=8``, and turning the part's termination off makes
  the reading worse rather than better.  It costs nothing now that the
  slip is measured against the array, and it is worth knowing before
  any of those three scripts is trusted again.
- **The strobe is read back, but only where the part drives it.**
  ``ruler.py``'s second row and ``drivemap.py``'s strobe map are the
  loopback again and read flat; the same readback shows the part's
  strobe as ``01010101`` and ``10101010`` at the offsets the read
  answer sits at.  So there is a reading of the strobe on a read and
  none on a write.
- **A freshly enumerated serial port hangs every gatecap resolve**,
  ``acrobe gatecap info`` and ``rates`` included, because the tty
  adapter does not put the port in raw mode and the port comes up in
  canonical discipline with echo.  ``stty -F /dev/ttyACM0 raw -echo``
  after every programming is the workaround; the fix belongs in
  acrobe's tty adapter.
- The **memory domain is 1.2% short** of 100 MHz, over fourteen
  endpoints at a tenth of a nanosecond, all of them the burst
  adapter's transaction address reaching a walker's hash.  The board
  says it costs nothing: the walkers pass at this occupancy, and what
  was failing on them was the pads.  Two queues were suspected of
  having caused it and neither did.  ``read_depth_c`` in the PHY is
  seventeen bits of shift register and a seventeen way mux of one bit,
  and deriving it from ``board_c.read_offset`` would save ten flip
  flops while costing a training sweep its reach past the record --
  which is the thing that made this board work at all, since the
  record was found by sweeping the whole port.  What the widening
  really deepened is ``read_ahead_c`` in the controller, whose read
  queue is fourteen cycles of a hundred and forty-four bits; thirteen
  is what a round trip of ``read_offset / 8 + 3`` asks for, so there
  are two cycles of margin in it and no more.  Both are left alone.
- **The global clock budget is a policy this design states and does not
  own.**  Four walker enables are held off the tree by name and
  ``replicate_resources`` takes the pressure off the rest, but three
  primaries still go to walker resets, which are not nameable.  Three
  builds in a row have now placed identically, which is new; a build
  whose netlist moves can still promote something else, so a report
  that has moved is worth reading at its global clock table first.
- **Programming this board from the Gowin programmer.**
  ``programmer_cli`` never opens the cable -- ``Error: Cable open
  failed`` -- while ``acrobe`` opens the same FT2232 and shifts JTAG
  on it.  The FT2232's second interface stays bound to ``ftdi_sio`` and
  appears as a ``/dev/ttyUSB``, which the vendor library does not
  detach and libusb does.  Unbinding it wants no root: ``acrobe -q
  info enumerate -r 'sp-<serial>/jtag(fmax=20M)'`` detaches the kernel
  driver through libusb, and ``programmer_cli --channel 0 --location
  4369 --device GW5AT-60B --operation_index 2 --fs <absolute path>``
  then opens the cable.  ``--scan-cables F`` reports that location;
  plain ``--scan-cables`` reports 0 and is wrong.  Retry once on
  ``OpenChain: TDO stuck``.  ``acrobe chip program`` reaches a GW5A
  over JTAG and takes a ``.fs`` as well.  Worth knowing either way: a
  ``programmer_cli`` that has been killed keeps the interface, and
  every later attempt then fails to open the cable for that reason and
  not for this one.
- Every data pin is pulled **down**.  ``ddr3_probe2.cst`` pulled DQ8
  the other way on purpose, to tell a silent part from a broken
  capture; that asymmetry belongs to a probe and not to a walk, where
  a pull fighting the part's own driver would do it on one line out of
  sixteen.  What separates the two cases here is ``first_read`` and
  the read count on the panel rather than a pull.
- ``dm_o`` leaves on the data pins' clock pair, which is right, but
  the mask pin is the one pin of the data group that cannot be read
  back.  ``poke.py`` runs its table either way of mode register 1 bit
  A11 for exactly that reason: a part with TDQS enabled supports no
  data mask, so a burst that lands only with the bit set says the mask
  pin was hiding it.
- The second SOM site is unpopulated and unconstrained.  A board with
  both fitted would want ``device_count`` above one, which
  ``nsl_ext_ram.ddr3`` carries and nothing here exercises.

Running it
==========

::

  gbs project build
  acrobe -q info enumerate -r 'sp-<serial>/jtag(fmax=20M)'  # frees the cable
  /opt/Gowin/current/Programmer/bin/programmer_cli \
      --channel 0 --location 4369 \
      --device GW5AT-60B --operation_index 2 \
      --fs /absolute/path/to/ddr3.fs
  stty -F /dev/ttyACM0 raw -echo   # or every resolve below hangs
  acrobe info adapters   # find the serial port the design brought up
  acrobe gatecap -r tty-<dev>/serial/chunked/gatecap info
  acrobe gatecap -r tty-<dev>/serial/chunked/gatecap rates

  acrobe run mpr.py       # the read path alone, against the part's own
                          # pattern: no write has to be trusted for it
                          # stride=N sets the coarse tap step
  acrobe run poke.py      # one burst written and read back, at the DFI
  acrobe run walk.py      # walk the whole part at the record's numbers
                          # size=0..3 picks the region: the probe, the
                          # whole part, every bank at row zero, or two
                          # rows in every bank
                          # count=N walks the region N times, one walk
                          # after another out of one session
                          # train=1 maps the read plane first, which is
                          # how the record's two read figures are found
  acrobe run eye.py       # the read plane, three ways, at length
  acrobe run dataeye.py   # the same plane against the array rather
                          # than against the part's own pattern: one
                          # walk of a region at every tap, counted
                          # size= picks the region, taps=a:b the span,
                          # odt= the part's termination, passes= how
                          # many walks a tap
  acrobe run drivemap.py  # which wire slots the pads hold
  acrobe run ruler.py     # where the write data sits against its command
  acrobe run level.py     # ask the part whether the strobe arrives
  acrobe run probe.py     # what the bus held at every read offset
  acrobe run taps.py      # the burst and the strobe at every tap
  acrobe run trace.py     # a pass of a walker, on the DFI: the first
                          # failing one, or the last clean one
                          # size= picks the region.  The probe's whole
                          # pass fits the window and is caught from
                          # the run; a larger region is caught on the
                          # walker's own error line with the window
                          # standing before it, pre= samples of it

The ``.fs`` path handed to ``programmer_cli`` has to be **absolute**.
``--scan-cables F`` is what says which cable and location to use;
plain ``--scan-cables`` reports location 0 and is wrong.  The
enumerate above is what detaches ``ftdi_sio`` from the cable's second
interface, which the vendor library will not do and does not need
root for.

The ``stty`` is not optional.  A freshly enumerated port comes up in
canonical discipline with echo, acrobe's tty adapter does not put it
in raw mode, and every resolve over it -- ``acrobe run`` included --
hangs before printing anything.

``walk.py`` reads the board record out of ``src/boundary.vhd`` rather
than repeating it, so a script that sweeps one figure puts the other
five back where the record leaves them and a report can say what it
was measured against.  Everything but ``walk.py`` in its default mode
sweeps something, so everything but that raises the panel's ``manual``
bit while it runs and puts it back down at the end.  A script stopped
part way leaves it up: the next ``walk.py`` then measures whatever
that script left, so program the part again before believing a walk
that followed one.

``poke.py``, ``level.py``, ``ruler.py`` and ``walk.py`` take the
strobe sense as a trailing ``0`` or ``1``; ``drivemap.py`` takes it
first and then the two leads.

The transport is the board's own USB2 port, not the debugger's.  The
``/dev/ttyACM`` it appears as exists only while a design driving it is
loaded, so a port that is absent after programming is a design that
did not come up rather than a cable.
