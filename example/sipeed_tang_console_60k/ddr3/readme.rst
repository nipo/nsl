=======================================
 DDR3 on a Tang Console 60k, by hand
=======================================

An H5TQ4G63EFR behind ``nsl_ext_ram.ddr3_io.ddr3_phy_serdes``, on a
Sipeed Tang Console 60K: two byte lanes, two strobe pairs, DDR3-800.

The same bench as ``example/xc7a50t/ddr3``, moved to a family whose
pins hold one clock pair each.  That single refusal is what the port
is about, and everything else here is the Artix bench with the data
bus twice as wide.

**The ladder has run as far as it goes.**  The rack answers, the
controller clock is the one the design was built for, the part is
alive and answers write levelling -- and no read of the array reaches
the fabric, at any of the sixty-four offsets the port could express then or
any of the two hundred and fifty-six taps of the line.  What stops it
is not a setting.  The design's own burst, read back on the pins it
leaves by, comes back with **every falling-edge beat missing**, and it
comes back **sixty-seven slots** from its command where the Artix's
comes back at thirty-three.  Either of those on its own empties the
read map.  The second has been fixed since -- the read offset carries
seven bits now and reaches seventy -- and the first has not.  So the
two read figures are still placeholders, and "What the ladder said"
below is why no measurement can replace them yet.

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
  board the strobe half of that reading is not there at all: the pin
  reads back flat at every slot while its own driver drives, which is
  in "What is open" below.
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
of the ladder the address map offers.

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
    read_offset => 61,
    read_tap => 0,
    write_slip => 8,
    dq_enable_lead => 0,
    dqs_enable_lead => 0,
    strobe_invert => false
    );

Four of the six are what the family says rather than what the board
says, and are known before a measurement:

- ``write_slip`` is **nominal**.  On the 7-series the data serialiser
  hands its parallel word across to a fast clock its parallel side
  does not run on, so the burst lands a whole cycle from where an
  aligned pair would put it and that board wants slip 0.  Here the
  data keeps the unshifted pair and the strobe's group is the one that
  crosses, so there is no whole-word transfer for the data to lose: a
  real ``OSER8`` takes its parallel word on a parallel edge.  Eight is
  no slipping at all.
- both **enable leads are zero**.  A GW5A pad's tristate is per pair
  and travels with the word its own serialiser presents.
- ``strobe_invert`` is **false**, which is the sense the schedule
  holds.

The two read figures are the measurement, and both are still
**placeholders**: the ladder has run and neither can be measured from
this design.

- ``read_offset`` was guessed a word above the Artix's 53, because the
  READ command leaves a cycle later through the crossing.  The board
  says the guess is not merely off but out of reach: the design's own
  write burst, timed against its own command, is at slot **67** where
  the Artix's is at 33, which puts a read answer near 69 -- past what
  the six bit port of the time could say.  The port carries seven bits
  now and reaches it; 61 is left where it was because the capture
  below is what stops the right number being measured.
- ``read_tap`` is sub-slot, on a line of **256 taps of about 12.5 ps**
  -- some two and a half beats of range, against the 7-series line's
  32 taps of 78 ps.  The line steps and wraps as it should; there is
  no window on the plane to place it in.

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

  logic       15393/59904   26%   (13381 LUT, 1442 ALU, 570 ROM16)
  register    13465/60780   23%
  CLS         14277/29952   48%
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

**The memory domain meets, to 0.4%**::

  board          50.000 MHz constraint   152.403 MHz actual
  mem           100.000 MHz constraint    99.623 MHz actual   TNS   -0.211 ns over 7 endpoints
  mem_shifted   100.000 MHz constraint   190.978 MHz actual
  usb            60.002 MHz constraint    60.307 MHz actual   met
  7 setup endpoints violated, 12 hold

Getting there took one constraint and two register stages, and the
constraint is the interesting one.

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

What that leaves is seven endpoints, all in the burst adapter's own
beat arithmetic, at a tenth of a nanosecond::

  -0.038  adapter/r.line -> walk/r.hashing_8          1
  -0.029  adapter/r.line -> adapter/r.line[20..25]    6

and the next paths after them are positive: the controller's own pick
feeding itself at +0.011, the other three walkers' hashes at +0.013 to
+0.022, the rack's APB bridge at +0.084.  The families this file used
to list -- the panel's counters off ``core/r.step``, the panel's
control into ``core/r.acc_address``, the walkers' comparison a
nanosecond out -- are gone from the report entirely.  ``mem``'s worst
path is twelve levels where it was fourteen, and 0.038 ns at twelve
levels is the placer's noise rather than a path.

All **twelve hold** violations are inside the vendor's soft
high-speed PHY, between its 60 MHz side and the 120 MHz side its own
``CLKDIV`` makes, on gray-coded FIFO pointers, as the fourteen before
them were.  ``ddr3_probe2`` shipped with them unanalysed -- it states
no clock for that domain -- and worked on this board.

What the constraint did not do is empty the primaries: the tool
promotes whatever is left, and this build spends them on the soft
PHY's link reset, a core state bit that drives 134 set and reset pins,
and the MPR readback's 144 way capture enable.  The first two are what
the resource is for.  The third is another enable, unnameable, and on
no failing path -- a reminder that naming nets one at a time is a
policy and not a fix, and that the policy is *a beat enable is not a
clock*.

One thing to know before reading any of these numbers twice: the
tool's placement of this design moves with the size of the changes
above.  Builds of it have read 98.935, 95.180, 93.671, 93.480, 88.609,
89.466 and now 99.623 MHz on ``mem`` while the failing paths stayed in
a handful of families, and ``board`` moved between 123 and 167 MHz and
``mem_shifted`` between 121 and 205 without either being touched.  At
48% of the part's CLS and with a clock of 8393 loads, a tenth of a
nanosecond of worst slack here is the placer's.  What the global-clock
policy bought is that the budget no longer moves with the netlist,
which is what made every earlier reading unrepeatable.

None of this has been tried on hardware.  What a 0.4% shortfall on the
controller clock costs is the burst adapter holding a beat count that
is a tenth of a nanosecond late, on a domain whose pins are placed and
whose crossings are checked.  It is the first thing to confirm once
the rack can be reached, and the last thing to suspect.

What the ladder said
====================

Every reading below comes off the committed bitstream, over the rack
on the board's own USB2 port.

**1. The transport and the clock.**  The rack enumerates and lists its
blocks -- the bridge, the enumerator, the clock measurer, the panel,
the register file, the capture and the DFI analyzer's three -- and the
measurer reads the controller clock at exactly what the design was
built for::

  clock,rate_hz
  ram,100000000

One thing the host tooling will not do here: ``acrobe gatecap -r
<path> info`` and ``... rates`` each hang before printing anything,
while the same resolve driven from ``acrobe run`` -- ``Session(path)``
and then the blocks' own console adaptors, which is the stack both
verbs use -- answers in seconds over the same transport.  Every
reading here was taken that way.

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

**3. The read map is empty.**  ``mpr.py`` maps all sixty-four offsets
against the line at eight taps a step, and then has nothing to
refine::

  sequencer step 7, 150 answers so far
    offset 0: nothing
    ...
    offset 63: nothing
  the pattern never came back whole.  What did, most often:
    0x00000000000000000000000000000000  at 2048 points
    a cycle of all ones or all zeroes is a bus nobody drove

Two thousand and forty-eight points and one word between them.  The
answers counter runs the whole time, so reads are being issued and the
PHY is announcing a capture for each of them; what the capture holds
is a bus nobody drove, on both lanes, at every offset and every tap.
A pass over the same plane printing the strobe words beside the data
says the same and adds that the strobe pins read ``00000000`` at every
one of those points too.

The instrument is not what is broken.  The panel's tick moves the
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

So the command pins are decoded, a mode register write lands, the
strobe arrives with edges on it and the part drives sixteen data pins.
Nothing in the empty map above is the part being absent, and the site
this bench drives is the fitted one.

The same passes say the strobe pin's own **readback is dead** --
``ever high 0x00, ever low 0xff`` on both lanes, while its own driver
is driving.  There is no reading of the strobe to be had on this
board, which takes ``ruler.py``'s second row and ``drivemap.py``'s
strobe map out of use.

**5. What the design's own burst says.**  ``ruler.py`` announces the
capture on the cycle of a *write*, so the pads' own receivers see the
burst the design is driving.  It comes back, and it comes back wrong
in two separate ways::

  --- poke value 0x40, capture announced on the write
  offset  data, earliest byte first                          strobe by lane
      59  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 41   00000000 00000000
      60  00 00 00 00 00 00 00 00 00 00 00 00 00 00 40 41   00000000 00000000
      61  00 00 00 00 00 00 00 00 00 00 00 40 40 41 40 41   00000000 00000000
      62  00 00 00 00 00 00 00 00 00 00 40 41 40 41 44 45   00000000 00000000
      63  00 00 00 00 00 00 00 00 40 41 40 41 44 45 40 41   00000000 00000000

**Every falling-edge beat is missing.**  A cycle is eight slots of two
lanes and the poke counts up, so slot *s* should read ``0x40 + 2s`` on
lane 0.  What offset 63 holds is::

  slot   0     1     2     3     4     5     6     7
  want   40    42    44    46    48    4a    4c    4e
  got    40    40    44    40    48    48    4c    48

Slots 0, 2, 4 and 6 are exactly right and 1, 3, 5 and 7 carry a copy.
Which side loses them is in *which* copy: slot 3 holds slot 0's word
rather than slot 2's, and slot 7 holds slot 4's rather than slot 6's.
A driver emitting only even beats would hold each for two slots and
give ``40 40 42 42 44 44 46 46``; a listener whose falling-edge half
updates once a half-cycle gives exactly what is there.  **The loss is
in the capture and not in the drive**, which is the one piece of good
news here: it leaves the write path unaccused.

It is also enough on its own to empty the read map.  The
multi-purpose register's predefined pattern alternates every beat and
is phase-locked to CK, and so are the slots this capture resolves: a
capture that answers on one CK edge and copies the other reads that
pattern as a constant at every offset.  Which is what it read.

**The burst is sixty-seven slots from its own command.**  The same
measurement on the Artix puts it at thirty-three to forty.  Sweeping
the slip moves it a slot a step and confirms the reading -- slip 12
puts it at 63, slip 8 at 67, slip 4 and slip 0 out past the end of the
window -- so what is deep is the pad path and not a slip that is
wrong.  A read answer belongs a slot or two past where the write data
sits, which is somewhere near **offset 69**, which is past what the
six bit ``read_offset_i`` of the time could say.  The port is now
``unsigned(6 downto 0)`` and the PHY's announcement queue reaches the
far end of it, so with the capture mended the offset can be pointed at
the answer.

**6. The poke does not land**, which follows from all of the above and
is here for the file::

  --- TDQS disabled: the mask pin is live
  value   read back                                       answers
   0x10   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00    49  0/16
   0x40   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   156  0/16
   0xa0   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00   157  0/16
    the answer does not move when the value does

with the TDQS bit set reading the same.  The walk was not run: a walk
checks a record, and there is no record to check.

What is open
============

- **The capture loses every falling-edge beat**, and that is the rung
  everything else waits behind.  A pad's ``IDES8`` and its ``OSER8``
  share a control set and therefore a clock pair on this family --
  which is why ``shift_strobe_c`` is true at all -- so what is wrong
  sits inside the one arrangement that builds and routes.

  What it is not: the wrapper's bit order.  ``IDES8``'s eight outputs
  come out oldest first with ``Q0`` the earliest bit on the wire --
  the two chains are cut alternately, deepest first, and within a
  stage the rising-sampled bit is the older of the pair -- and
  ``serdes_input_gowin`` binds ``Q0`` to ``parallel_o(0)`` under
  ``left_first_c``, which is what the package contract and the
  simulation architecture both mean by it.  Checked bit by bit against
  ``prim_sim.v`` for GW1N, GW2A and GW5A; all three agree with the
  wrapper.  What the comparison did turn up is that Arora V's
  ``IDES8`` carries one shift stage more than the older families', so
  a GW5A capture arrives two slots later than the behavioural blocks
  in ``nsl_io`` say -- two slots of the sixty-seven, and not the
  falling-edge half.  ``DESIGN.md`` section 12 has both.

  ``example/sipeed_tang_console_60k/serdes_pin_probe`` now carries the
  loopback that would settle it -- one word driven out of an
  ``OSER8`` and read back at the same pad through the ``IODELAY`` and
  the ``IDES8``, on a header pin and on a DDR3 pin at once, over every
  tap -- and it is unread: the UART pin that report leaves on stopped
  reaching the debugger's receiver after its first reading.  Its
  README has what was tried.  The transport that would unblock it is
  the one this bench already has.
- **The read offset now reaches the answer.**  The write burst alone
  is sixty-seven slots from its command on this family, so a read
  answer is near seventy, which a six bit ``read_offset_i`` could not
  say.  The port, the panel's field, the board record's use of it and
  both benches' scripts carry seven bits now, and the PHY's
  announcement queue was deepened to seventeen cycles so that a sweep
  of the whole port has somewhere to read out of.  This board's
  controller asks for nineteen cycles of read ahead for the same
  reason.  The two read figures of the board record are still
  placeholders, because the capture below is what stops them being
  measured.
- **There is no reading of the strobe.**  The strobe pin reads back
  flat at every slot while its own driver is driving, so nothing here
  times the strobe against the data or shows the strobe's driven
  window.  That readback is the one path in this design that rides the
  shifted pair and crosses back to the controller clock in a single
  register, and it is the only instrument of the set that does not
  work.
- ``acrobe gatecap info`` and ``rates`` hang on this transport, where
  the same blocks answer through ``acrobe run`` in seconds.  It is a
  host-side difference between the two resolve paths and not the
  board's.
- The **memory domain is 5% short** of 100 MHz, and what it costs.
  None of it is this bench's own logic: it is thirty-three endpoints
  inside ``axi4_mm_burst_adapter``'s beat arithmetic reaching the
  walkers' hashing, worst -0.521 ns on a path of eleven levels,
  -8.7 ns over all of them.  A build before the read offset was
  widened had seven such endpoints at -0.038 ns, and the queues that
  widening deepened -- seventeen cycles of announcement in the PHY,
  thirteen of read ahead in the controller -- are what moved it.  The
  placer is noisy at this occupancy and this is more than noise; what
  a beat count half a nanosecond late does to a cadence is still a
  prediction until a read comes back.
- **The global clock budget is a policy this design states and does not
  own.**  Four walker enables are held off the tree by name; every
  other high-fanout net is the tool's to promote, and this build spends
  a primary on the MPR readback's capture enable.  A build whose netlist
  moves can promote a different one, so a report that has moved is
  worth reading at its global clock table first.
- **Programming this board from the Gowin programmer.**
  ``programmer_cli`` never opens the cable -- ``Error: Cable open
  failed`` -- while ``acrobe`` opens the same FT2232 and shifts JTAG
  on it.  The FT2232's second interface stays bound to ``ftdi_sio`` and
  appears as a ``/dev/ttyUSB``, which the vendor library does not
  detach and libusb does; unbinding it wants root.  ``acrobe chip
  program`` reaches a GW5A over JTAG and takes a ``.fs``, so that is
  the way in once the board answers.  Worth knowing either way: a
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
  /opt/Gowin/current/Programmer/bin/programmer_cli \
      --device GW5AT-60B --operation_index 2 --frequency 15MHz \
      -f /absolute/path/to/ddr3.fs
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
  acrobe run drivemap.py  # which wire slots the pads hold
  acrobe run ruler.py     # where the write data sits against its command
  acrobe run level.py     # ask the part whether the strobe arrives
  acrobe run probe.py     # what the bus held at every read offset
  acrobe run taps.py      # the burst and the strobe at every tap
  acrobe run trace.py     # a pass of the probe walker, on the DFI: the
                          # first failing one, or the last clean one

The ``.fs`` path handed to ``programmer_cli`` has to be **absolute**,
and ``--scan-cables`` is what says which cable and location to use.

Those last two hang on this transport and print nothing.  A script run
under ``acrobe run`` that opens ``Session(path)`` and asks each block's
console adaptor answers in seconds over the same port, which is what
every reading below the transport was taken with.

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
