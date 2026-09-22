=====
Gowin
=====

Rules for Arora V (GW5A) unless another family is named, checked
against Gowin IDE V1.9.12 and the models under
``/opt/Gowin/*/IDE/simlib``.  Measured figures come from a Sipeed Tang
Console 60K (GW5AT-60B) driving an H5TQ4G63EFR at DDR3-800.

IO logic
========

**A pin's two serialisers share one control set, and therefore their
clocks.**  A pad driven from one clock pair cannot be listened to on
another: an output serialiser on a shifted fast clock beside a capture
on the unshifted one is refused by the circuit check at the end of
synthesis, before place and route, with ``(CK0012) ... has different
control net from instance ... connected to the same buffer``.  This is
why ``nsl_ext_ram.ddr3_io.ddr3_phy_serdes`` carries ``shift_strobe_c``
at all: a data pin keeps one clock pair for both directions, so the
quarter period a DDR3 write needs leaves on the strobe, CK and the
command pins.  Measured by ``serdes_pin_probe`` under
``example/sipeed_tang_console_60k``.

**A pin's IO logic will not take an input serialiser beside an output
register on another clock, nor two input serialisers.**  Both are
refused rather than silently mis-built, so a data lane migrates to the
memory primitives all at once or not at all.

**One clock pair through the whole of a pin's IO logic builds and
routes** -- output serialiser, ``IODELAY`` and input serialiser --
and so does a pair whose parallel clock comes from the pad logic's
``CLKDIV`` rather than the PLL.  The tools accept the second
arrangement; the next rule is why it misbehaves anyway.

**A serialiser needs a settled relationship between its fast and its
parallel clocks.**  A shifted fast clock against a parallel clock
divided from an unshifted one makes the block hold a stale word, some
65 ns past its eight beats on the Tang Console; on one pair it emits
exactly eight beats and stops.  A strobe wanting a phase of its own is
better built from a double rate register, which takes no parallel
clock.

**A pad's enable must come from its own serialiser's tristate
output**, not from a fabric signal: ``CK0011`` otherwise.  And **a
clock cannot be assigned at a pin**: a forwarded clock comes from a
serialiser pattern like any other signal.

**A pad does not hear its own driver at beat rate.**  Snooping a pin
by capturing it while the design drives it is a standard bring-up
instrument on 7-series, and on Arora V it lies: at 800 MT/s a pad's
receiver does not resolve the 1.25 ns beat out of its own driver's
waveform, and returns each even beat twice in place of the odd one.
Nothing in the tools objects.  What excludes a real capture fault:
the delay line cannot undo it, though its 256 taps span some three
beats and the window walks monotonically; the whole-slot slip cannot
undo it either; and the part's own patterns -- its multi-purpose
register, its strobe, a burst read back from the array -- come back
whole through the same pin, the same delay line and the same input
serialiser.  So an instrument that reads the bus while this design
drives it measures the receiver, not the bus.  Use the part as the
reference: train reads on the multi-purpose register and place a
write by reading it back out of the array.  Cost of believing the
loopback: two sessions spent hunting a lost falling edge that was
never lost.  Measured on the Tang Console 60K.

**A pad's output slew defaults to SLOW, and a slow edge is most of a
beat.**  At 800 MT/s a 1.25 ns beat does not survive it: a written
zero comes back as a one whenever the next beat on that pin is a one,
never the other way round, on whichever few pins are worst.  The fault
does not move with the delay line -- the error count stays flat across
the whole tap window, so it reads as neither a sampling point nor a
phase -- and it survives every slip, which is what tells it apart from
a placement of the burst.  `SLEW_RATE=FAST` on the bus is the fix, and
it moves the read answer a beat earlier, so the board record wants
re-measuring after it.

Nothing announces the default: the flow raises no message, the netlist
does not carry the attribute, and no simulation models a pad's edge.
The **Slew Rate column of the pin report** is the only place it
appears, and is worth reading on any bus running faster than a few
hundred megabits.  SUG1018 §2.5 lists the parts that take the
attribute; the GW5AT-60 is one.  Measured on the Tang Console 60K,
where it was the whole of a 4.5% beat error rate.

**There is no output delay line, so an output pad's skew has to come
out of the schedule.**  ``IODELAY`` sits on inputs; a gate between a
serialiser and its pad is a route that does not exist, and ``DRIVE``
is refused above the standard's own list -- ``(CT1108) Illegal port
attribute value specified``.  So when a pad is far enough from its
group to miss a part's input setup, nothing at the pin will fix it:
not the slew, which may already be fast, not the drive, not placement
when the tools already put its IO logic on the same clock spur as the
rest.  On the Tang Console one address pin sits eight IOLOGIC sites
from its group and twenty-three from the forwarded clock, and the part
sampled it low where it was driven high, on the one command that reads
it.  A tick-rate command serialiser gives a pin only half a tick
either side of the clock edge, which is all the setup there is; the
fix was to present the address on the idle tick before its command as
well, which costs nothing while the controller issues one command a
cycle.  ``ddr3_phy_serdes``'s ``early_address_c`` is that.  The
symptom of a margin this thin is an error rate that swings fiftyfold
between builds rather than one that is simply present or absent.

**A command pin cannot be driven at cycle rate.**  Chip select held
low for a fabric cycle hands the part the same command once per tick
of that cycle, and a serialised select beside registered address and
control arrives cycles apart, so the pulse lands after its address has
moved on.  Address, control and CS all go on tick-rate serialisers.

Input serialiser word order and depth
-------------------------------------

``IDES8`` hands its outputs over oldest first, ``Q0`` the earliest bit
on the wire; ``CALIB`` slips the word by one bit and does not reorder
it.  ``serdes_input_gowin`` binds ``Q0`` to ``parallel_o(0)`` under
``left_first_c``, which is what ``nsl_io.serdes`` means by it, checked
against ``prim_sim.v`` for GW1N, GW2A and GW5A.

**Arora V's input serialiser is one fast cycle deeper than the older
families'.**  GW1N and GW2A hold four shift stages a side and cut the
word out of ``Dd0_reg0..3``/``Dd1_reg0..3``; GW5A holds five and cuts
it out of ``d0_reg1..4``/``d1_reg1..4``.  The same wire reaches the
fabric **two slots later** here, and
``lib/nsl_io/serdes/serdes_blocks_gowin.vhd`` holds the GW1N/GW2A
model, so simulating a GW5A netlist against it is two slots optimistic
about when a capture arrives.

Delay line
==========

**The delay line takes its tap two ways, and only one at a time.**
With ``DYN_DLY_EN`` true, ``ADAPT_EN`` false and ``SDTAP`` low,
``DLYSTEP`` *is* the tap, applied as given -- what
``nsl_io.delay.input_delay_variable`` counts into it.  ``SDTAP`` high
starts a loop of the block's own that creeps one tap per eight data
edges towards ``DLYSTEP``, reaches the line only under ``ADAPT_EN``
and cannot be given a position.  Driving both gets neither.

**The silicon follows the tap input continuously; the vendor's
simulation model does not.**  In ``prim_sim.v``, ``IODELAY``'s
``delay_data`` is latched inside ``always @(SDTAP or VALUE)``, so with
both pins static a change of ``DLYSTEP`` never reaches it; the only
``DLYSTEP``-sensitive path feeds ``delay_data_adapt``, which
``ADAPT_EN = "FALSE"`` gates out of ``delay_data_real``.  A GW5A
netlist simulated against the model shows a delay line frozen at one
tap while the board sweeps.

Range measured on the Tang Console: **256 taps spanning about three
1.25 ns slots, some 14.6 ps a tap**, against the ~12.5 ps of UG304
*Arora V Programmable IO* §4.4.1 tables 4-46 and 4-47 -- also the flat
step the model writes into its own delay expression.  **There is
nothing to calibrate**: no block sits beside the line to lock it to a
reference, so ``nsl_io.delay.delay_reference`` here is
``ready_o <= reset_n_i``.

**The tap is a fabric path into the pin's own capture**, worth 4.0 ns
of negative slack on every data pin of a GW5AT-60B: the tap register
sits in the fabric domain, the line adds most of a nanosecond, and the
input serialiser behind it samples at the memory rate.  A 7-series
``IDELAYE2`` takes ``CE``/``INC`` pulses in the capture's own domain
and has no such path, so this appears on porting and nowhere before.

On the ``DQS`` memory blocks, which ``ddr3_phy_serdes`` does not use:
**DLLSTEP must come from a DDRDLL** or placement fails outright,
``PR0015`` -- it is a shared delay reference, not a per-lane knob --
and its step measures **~14.6 ps** on the Tang Console, one 2.5 ns
memory period every ~170 steps, DQS crossing CK at step 150 on one
lane and 151 on the other.  The read capture gate there is a
one-cycle pulse and not a window (``READ = {4{read_line[i]}}``), so
gate training is coarse cycle by ``RCLKSEL`` quarter tick.

Clocks
======

**A PLL output that misses the solver's grid is left disabled, not
approximated.**  Every ``CLKOUTn_EN`` reading ``TRUE`` in the netlist
is therefore the check that a clock plan is buildable rather than
merely asked for; a non-integer rate silently costs an output.  The
phase grid is eighths of a VCO cycle: the Tang Console plan -- 50 MHz
in, 100 / 400 / 400@1/4 / 100@1/16 out -- lands on a 1200 MHz VCO with
divisors 12, 3, 3, 12 and ``CLKOUT2_PE_FINE`` = ``CLKOUT3_PE_FINE`` =
6, six eighths of a VCO cycle being 625 ps: a quarter of a memory
period, stated once per clock.  Two shifts landing on the same number
is what says the pair moves together.

**The placer promotes high-fanout enables onto the global clock
tree.**  A GW5AT-60 has eight *primary* global clock resources and
eight *long wires*, handed to whatever net has the fanout -- a clock
enable or a set/reset as readily as a clock.  On the Tang bench two
beat enables of 189 and 334 clock enables took primaries beside the
design's four real clocks: 8 of 8 used, the whole device placed
differently for it, and the memory domain 10 MHz and 573 endpoints
worse than the same netlist with 6 of 8 used.  **A timing report that
has moved is worth reading at its global clock table first.**

The lever is ``CLOCK_LOC "<net>" LOCAL_CLOCK;`` in the physical
constraints: SUG1018 *Arora V Design Physical Constraints User Guide*
§2.7, "LOCAL_CLOCK means this net is not routed to the global clock
wire", taking no ``signal_type`` in that form, and SUG113 *Gowin FPGA
Design User Guide* §4.3.2 prescribes it by name when clock resources
are exceeded.  There is no synthesis counterpart -- SUG550 lists
``syn_maxfan`` and nothing that says *not a clock* -- because the
promotion is the placer's.  Name every instance of a repeated block
rather than the ones a given build promotes.  Leave set and reset nets
on the tree, which is what the resource is for; a net synthesis named
``nNNN_5`` cannot be constrained at all.

**A build that places differently is a different design.**  Left
alone, the placer will spend primary global clock resources on
whatever has the fanout for it, and on this family that is usually a
bench's walker resets.  With eight primaries gone the real clocks fall
back to long wire, the device re-places around them, and the result is
not slower by a little: one such build read 86 MHz on a 100 MHz domain
and returned a corrupt descriptor over its debug link.  Since the nets
that win are exactly the ones synthesis leaves unnameable, the lever
is not more ``CLOCK_LOC``: it is ``replicate_resources: 1``, which
splits a high-fanout driver so no copy is worth promoting, with
``place_option: 3`` beside it.  Four consecutive builds placed
identically after that, where the readings before it spread over
ten megahertz.  Read a moved timing report at its global clock table
first, before believing anything else in it.

**Not every board oscillator reaches a global clock network.**  The
Tang Console's 50 MHz input is ``V22``, an ``EMCCLK`` pin and not a
``GCLK``, so a clock buffer on it lands on long wire: ``(PR1014)
Generic routing resource will be used to clock signal``, ``LW`` in the
PnR global clock table.  Logic there runs off a PLL output.

Tools
=====

* **A black box will not take an expression as an actual** in a port
  map: ``not x`` has to go through a signal.
* **A clock cannot be stated at a net a VHDL design names** when
  several come out of one block.  ``pll_multi`` hands its outputs over
  as a vector and the scalar each is read out of does not survive
  synthesis, so ``create_clock ... [get_nets {ram_s}]`` is refused
  with ``(TA2003) Can't set timing constraint to object ram_s``,
  before placement.  State each clock at the pin that drives it --
  ``<pll>/use_plla.inst/CLKOUT0`` and siblings, a buffered board clock
  at ``<buffer>/is_global.buf/CLKOUT`` -- which are names the netlist
  keeps, and which the tool gives a default rate the file corrects.
* **The SDC parser takes no line continuation.**  A
  ``set_clock_groups`` split over several lines with a trailing
  backslash is ``(TA2000) 'syntax error' near token '\'``.
* **A primitive's reset pin is RESET, and NSL's generated CDC cut
  names CLEAR.**  The generator cuts an asynchronous reset's fanout at
  ``*tig_reg_clr*/CLEAR``, which covers fabric registers and misses
  every serialiser in a pad; the reset release then reads as negative
  slack across the whole bus.

Programming
===========

It reads as a dead board, so: **programming does not need root.**
``programmer_cli`` fails with ``Error: Cable open failed`` while the
FT2232's second interface is bound to ``ftdi_sio``, which the vendor
library will not detach.  Enumerate the adapter through ``acrobe``
first -- libusb detaches the kernel driver -- then::

  /opt/Gowin/current/Programmer/bin/programmer_cli \
      --channel 0 --location <n> --device GW5A-60B \
      --operation_index 2 --fs <absolute path to .fs>

The ``--fs`` path has to be absolute.  ``--scan-cables`` alone reports
location 0 and misleads; ``--scan-cables F`` reports the real one.  A
``programmer_cli`` that has been killed keeps the interface, and every
later attempt then fails to open the cable for that reason.
