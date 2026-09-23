======
Altera
======

Rules for Cyclone 10 LP unless another family is named, checked
against Quartus Prime 24.1std on a ``10CL025YU256C8G``.  Figures that
were read come from the Intel Cyclone 10 LP Device Datasheet
(C10LP51002) and the Intel MAX 10 Clocking and PLL User Guide
(UG-M10CLKPLL), whose PLL is the same block; figures that a tool
reported name the report they came out of.

Cyclone 10 LP is Cyclone IV E silicon.  Its component declarations
live in ``/opt/Altera/prime/quartus/eda/sim_lib/cyclone10lp_atoms.vhd``
and ``cyclone10lp_components.vhd``, with the megafunctions in
``altera_mf_components.vhd``.

Megafunctions and atoms
=======================

**A megafunction is instantiated as a plain component, with no
library clause.**  Quartus binds ``altpll`` by name out of its own
megafunction library, the same way it binds a device atom.  Only the
generics and ports a design drives need declaring: every input of
``altpll`` has a default and every output may stay open, except
``inclk0_input_frequency``, which has none and is the reference
*period in picoseconds*.

**Prefer the megafunction to the atom it wraps.**  ``cyclone10lp_pll``
takes its counters already encoded -- ``c0_high``, ``c0_low``,
``c0_initial``, ``c0_mode``, the VCO phase tap -- along with
``charge_pump_current`` and the two ``loop_filter_*`` settings that
the VCO rate calls for.  Those encodings are neither documented nor
stable across the family, and a wrong loop filter builds a PLL that
elaborates, fits and locks badly.  ``altpll`` derives all of them
from ratios, and carries the same shape on Cyclone IV E and MAX 10.

PLL
===

**The counter chain is N, M and C, all 1 to 512.**  N pre-scales the
reference into the phase-frequency detector, M closes the feedback,
and five post-scale counters C0 to C4 carry the outputs.  A C counter
reaches 512 only at a 50% duty cycle; anything else caps it at 256
(UG-M10CLKPLL table 4).

**The PFD floor is 5 MHz and its ceiling 325 MHz; the oscillator runs
between 600 and 1300 MHz** (C10LP51002 table 21, the same for every
speed grade).  A 12 MHz board oscillator clears the PFD floor with N
at 1, which leaves the whole VCO window reachable in 12 MHz steps --
the floor constrains nothing on such a board.  Note that the floor is
on the PFD input, so a reference under 5 MHz is unusable outright: N
only divides it further down.

**What Quartus calls the nominal VCO frequency is not the
oscillator.**  Between the oscillator and both the C counters and the
M feedback sits the VCO post-scale counter K, which either passes the
oscillator through or halves it.  The rate the counters divide is
therefore the PFD rate times M, and the oscillator runs K times that.
The PLL Summary of the fitter report states the former under "Nominal
VCO frequency" and K beside it.  A 12 MHz reference asked for 80 MHz
comes back as M = 40, N = 1, C0 = 6, K = 2 and a nominal VCO of 480
MHz -- 120 MHz under the datasheet's floor, because the oscillator is
at 960.  The datasheet says as much in a footnote to table 21 and
nowhere else.

**So the window a solver must honour on the counters' node is 300 to
1300 MHz**, not 600 to 1300: K at 2 maps the oscillator's 600 to 1300
onto 300 to 650 there, and the two overlap into one contiguous range.
Asking for 600 kHz off 12 MHz proves the bottom of it -- the only
mapping is M = 25, C0 = 500, which Quartus builds with K at 2 and
reports as a 300.0 MHz nominal VCO.  ``nsl_clocking.pll``'s Cyclone 10
LP backend states that window, and ``tests/pll_solve_cyclone10lp``
pins both edges.

**Phase shift is stated in picoseconds and snapped to an eighth of a
VCO period.**  Since the VCO rate is the fitter's to choose -- it is
free to pick any M and C realizing the ratio it was handed -- an exact
fraction of an output cycle cannot be promised from the ratio alone.
The fitter reports the step it ended up with: 260 ps for the 80 MHz
case above, 416 ps for the 600 kHz one.

**Output rate has a ceiling the counters do not express**: 402.5 MHz
to a global clock on a -C8 part, 472.5 MHz on a -C6, 450 MHz on -I7
and -A7.  Nothing in the counter ranges or the VCO window catches a
request above it, so the fitter is what rejects one.

**Handing ALTPLL a ratio leaves the counters to Quartus.**
``clk0_multiply_by`` and ``clk0_divide_by`` state the output rate over
the reference, and the fitter picks an N, M and C realizing it, which
need not be the pair a solver had in mind: 12 to 80 MHz goes in as 20
over 3 and comes out as M = 40 over C = 6 where the mapping said M =
100 over C = 15.  Both are legal and the rate is identical, since the
ratio is exact.  What the ratio does not carry -- that the request is
reachable at all -- is what a topology is for.

**A ratio given for an output whose port is unused is a warning.**
Passing ``clkN_multiply_by`` alongside ``port_clkN => "PORT_UNUSED"``
draws ``(15899) ... has parameters clk1_multiply_by and clk1_divide_by
specified but port CLK[1] is not connected``.  VHDL has no way to
leave a generic unassociated per instance, so a wrapper covering a
variable number of outputs takes the warning.

**Measured on silicon: a 12 MHz reference asked for 80 MHz comes back
at 80.000000 MHz.**  The ratio is exact and the reference is a crystal
oscillator, so there is nothing left for the block to be wrong by that
a rate counted against that oscillator would not show.  It was read
with a ``gatecap.clock_measurer`` riding the oscillator rather than
the PLL, under ``example/trenz_tei0003/clock_check``.

DDR output
==========

**ALTDDIO_OUT is the block, and it goes in as a plain component like
ALTPLL.**  ``width`` is the only generic with no default; every input
holds a safe value and every output may stay open.  ``dataout``
carries ``datain_h`` while ``outclock`` is high and ``datain_l``
while it is low, so the half that reaches the wire first is the ``_h``
one.

**Prefer it to the cyclone10lp_ddio_out atom underneath.**  The atom
carries ``clkhi``, ``clklo``, ``muxsel`` and a
``use_new_clocking_model`` switch, whose combinations decide which of
the two output registers reaches the pad in which half period.  None
of that encoding is documented, and the fitter derives all of it from
the megafunction.

**Measured on silicon**, on a CYC1000: fed the two constant halves a
forwarded clock is made of, the block puts a square wave at the whole
clock rate on the pin -- 80 MHz off an 80 MHz clock, which is twice
what an output register on that clock could reach.  The pin was
driven and read back through its own input buffer, so what was
counted is the pad and not the net driving it, and holding both
halves equal stops it.  That round trip needs the pin to be a real
bidirectional one: the output enable is the PLL's lock rather than a
constant, and the fitter then reports ``bidir`` for it and places a
``ddio_outa`` cell on its IOE.

The VHDL front end
==================

Quartus's VHDL analyser is the loosest part of the toolchain, and
three of its gaps are things the language allows and every other tool
in this tree accepts.  All three are elaboration-time: they cost a
build, not a board.

**A zero-length array generic is refused.**  Passing an array whose
range is null -- the empty case of a generic that sizes a boundary --
fails with ``Error (10515): VHDL type mismatch error ...: integer type
does not match string literal``, followed by ``Error (12152): Can't
elaborate user hierarchy``.  The message names neither the generic nor
the type, and its line number points past the end of the instantiating
file, so it reads as a syntax error somewhere else.  Nine lines
reproduce it: a package holding ``constant empty_c : integer_vector(0
to -1) := (others => 0);``, an entity with ``generic (v_c :
integer_vector := empty_c)``, and an instance passing it.

The way round it is to give the boundary at least one element.  A
gatecap control/status panel with no tick signal at all hands its
shell two null generics, which is why the bench under
``example/trenz_tei0003/gatecap_uart`` carries a tick out and a tick
in whether or not its panel needs them.

**A use clause naming a type does not make that type's enumeration
literals visible**, though VHDL 10.4 says it does.  ``use
some_lib.some_pkg.some_enum_t;`` followed by a bare literal gives
``Error (10482): object "LITERAL" is used but not declared``.  Import
the whole package instead.  The same applies to an expanded name:
``some_lib.some_pkg.LITERAL`` is refused the same way, so a default
generic value written that way -- the usual form when a package is
imported by selection rather than wholesale -- has to be rewritten
too.  ``nsl_memory.rom`` and ``nsl_uart.serdes`` carried both shapes.

**An alias whose subtype has a null range is refused**, with ``Error
(10290): VHDL Alias Declaration error ...: alias target name does not
have the same number of elements as the alias subtype``.  This bites a
subprogram that aliases an argument into a known index direction and
is called with an empty one, which is what ``nsl_data.crc``'s
``crc_params`` does with its optional ``init`` and what
``nsl_ext_ram.dfi``'s ``data`` and ``to_data_vector`` do with their
optional write mask.  A constant declared from the argument copies
position-wise, which is what the alias gave, and takes a null range
without complaint.

Synthesis
=========

**A bit that one path of a function leaves alone becomes a register
and a latch, and the latch is clocked by data.**  A function that
writes some bits of its result and returns the rest of its argument
untouched -- the shape of a byte-addressed field assembler -- reads to
Quartus as a register that both loads and holds asynchronously.  It
builds that as ``Warning (13004): Presettable and clearable registers
converted to equivalent circuits with latches``, one ``Warning
(13310)`` per bit, and the emulating latch takes its clock from the
index signal, which is combinational.  The timing analyser then
reports that index as an unconstrained clock, and the field takes
whatever a glitch on it presents.

This is silent: the design builds, meets timing with room to spare,
and answers.  Measured on a CYC1000, an APB bridge whose address
register was built this way served every read from address zero and
failed every write, which reads from the host as a rack that
enumerates, reports a plausible fingerprint, and then returns the
descriptor ROM for every register in it.  That build met timing with
70 ns of slack on an 83 ns period.

Assigning every bit on every path removes it, and is what
``nsl_amba.stream_apb``'s ``byte_set`` now does.  Sixty lines
reproduce both the fault and the cure.  The NSL reset idiom is not
involved: the conventional ``if reset then ... elsif rising_edge``
template makes no difference either way.

**Unused bits of a partially used vector become latches too**, with
``Warning (10631) ... holds its previous value in one or more paths``.
Where those bits are never read this is cosmetic, and a generated rack
carrying a one-bit signal in a 32-bit word produces 31 of them per
word.

Clock networks
==============

**The fitter assigns clock networks itself**, from the fanout of every
net it finds driving a clock port, and a dedicated clock pin reaches a
global network that way with nothing in the netlist asking for it.
``nsl_clocking.distribution``'s ``altera`` arm is therefore a
pass-through, and a 12 MHz pin clocking a whole gatecap rack through
it closes timing with 70 ns of slack on an 83 ns period.

``altclkctrl`` would instantiate the way ``altpll`` does above, but it
is a clock *selector* and *gate*: it has an enable and a select, and
``clock_buffer`` has neither to give it.  A design that needs a
promotion the fitter did not make asks for it where the fitter reads
its instructions::

  set_instance_assignment -name GLOBAL_SIGNAL "GLOBAL CLOCK" -to <net>

Instrumenting a board
=====================

**An instrument's clock must not come from the thing it measures.**
A gatecap rack riding a PLL output reports that PLL's rate correctly
by construction and says nothing; worse, a PLL that came up wrong
takes the link down with it, so the one situation the instrument
exists for is the one where it is silent.  Both CYC1000 benches
therefore ride the 12 MHz oscillator: the transport's baud rate, the
rack's core and the measurer's reference are all that pin, and only
the thing under measurement is on the PLL.

That makes every panel register a clock-domain crossing, which on
this vendor is worth saying out loud given that none of NSL's CDC
attributes are honoured here.  In practice the two clocks share a
PLL, so Quartus times the crossing rather than ignoring it, and on a
12 and 80 MHz pair it is the design's worst path: the closest edges
the two rates make are 4.16 ns apart, which is what the crossing gets
whatever the 83 ns period suggests.

Internal oscillator
===================

**The ``cyclone10lp_oscillator`` atom is usable from the fabric.**
It is the oscillator the part runs active serial configuration from;
``oscena`` held high keeps it running after configuration, and
``nsl_clocking.oscillator``'s ``clock_internal`` backend does exactly that.

**It runs faster than Quartus believes.**  The timing model caps the
atom at about 46 MHz through its minimum pulse width, while a 10CL025
on a CYC1000 measures about 65 MHz, read as the throughput of an SPI
master it clocks at known divisors.  A design on it cannot be
constrained at the real rate without failing that check, so constrain
it lower and keep the fabric paths well inside the real period.

User JTAG
=========

**The user chains hang off the ``cyclone10lp_jtag`` device atom.**
It is the Xilinx ``BSCANE2`` of this family, and instantiating it
inserts no SLD hub -- which also means SignalTap and anything else on
virtual JTAG is gone from that design.  Its ``tck``, ``tms``, ``tdi``
and ``tdo`` must reach top-level ports named ``altera_reserved_tck``,
``_tms``, ``_tdi`` and ``_tdo``; Quartus places those on the dedicated
JTAG pads itself and they need no location assignment.

**The IR is 10 bits; USER0 is ``0x00C`` and USER1 ``0x00E``.**  The
atom hands the pad signals back as ``tckutap``, ``tmsutap`` and
``tdiutap``, and offers ``shiftuser``, ``updateuser`` and
``runidleuser`` qualified by "IR is USER0 or USER1", with
``usr1user`` telling the two apart.  There is no capture strobe and no
USER0 select, so a register that must load a value before it shifts
out needs fabric that tracks the TAP state and the IR.
``nsl_jtag.user_tap``'s backend does exactly that and uses none of the
qualified outputs.

**``tdouser`` is launched on the falling edge of TCK.**  The atom
routes it to the TDO pad while a user IR is selected, and the host
samples on the rising edge.

**TCK is a clock like any other.**  ``create_clock`` on
``altera_reserved_tck`` and an asynchronous group against the fabric
clock is all the timing analyser needs; the pads themselves stay
unconstrained.  On a CYC1000 at 12 MHz the TCK domain closes with 40 ns
of setup slack, and gatecap's JTAG transport enumerates, round-trips
panel registers and survives a reconfiguration over the same TAP.

External memory
===============

**A clock forwarded through a DDR output is a generated clock, and an
inverted one.**  Handed the two constant halves a clock forward is
made of, the block puts the fabric's clock on the pin upside down, so
the pin's own clock is::

  create_generated_clock -name ram_clk \
    -source [get_pins {<pll instance>|inst|auto_generated|pll1|clk[0]}] \
    -invert [get_ports ram_clock_o]

The source is the PLL's output pin -- ``derive_pll_clocks`` names the
domain after the same node -- and the clock buffer between the two is
a pass-through that leaves no node to hang it on.

With that in place the memory bus constrains the ordinary way, and
both directions land where they belong: the driven pins are analysed
under ``ram_clk`` with half a period of relationship, which is the
margin the half-period clock forward buys; the read pins are launched
by ``ram_clk`` and captured under the PLL's domain, since the PHY
catches them on its falling edge.  An 80 MHz W9864G6JT on a -C8
closes both, with the part's 1.5 ns of setup and 1 ns of hold as
output delays and its 6 ns access time and 3 ns output hold as input
delays.

Project settings
================

**An unused pin is driven to ground by default.**
``RESERVE_ALL_UNUSED_PINS`` defaults to ``AS OUTPUT DRIVING GROUND``,
so every pin the design does not mention fights whatever is on the
other side of it.  On a board whose FPGA reaches an SDRAM, a sensor
and a USB bridge's modem lines, that is most of the package.  Set it
to ``AS INPUT TRI-STATED`` in the project's pin assignments.

**Quartus honours a VHDL signal's initial value as its power-up
state.**  ``nsl_clocking.reset``'s ``reset_at_startup_generic`` falls
through for this hwdep and works: its shift register starts at zero,
converges on the alternating pattern it watches for, and releases the
design.  Measured on a CYC1000.

Attributes
==========

Quartus recognises none of ``syn_srlstyle``, ``syn_preserve``,
``shreg_extract``, ``async_reg`` or ``nomerge``, and says so once per
occurrence with ``Warning (10335): Unrecognized synthesis attribute``.
The clock-domain-crossing registers NSL marks with them are therefore
unprotected against retiming and merging here.  Nothing in this tree
relies on that protection yet; a design that does wants
``set_instance_assignment -name PRESERVE_REGISTER ON`` and ``-name
DONT_MERGE_REGISTER ON`` on the crossing.
