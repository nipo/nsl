=================
 PTP grandmaster
=================

Goal
====

GPS-disciplined PTP grandmaster on the Arty A7-35 with the ArtySync
shield: the NEO-M8Q's time pulse disciplines a VCXO-derived time
base, its serial stream names the seconds, and the PTP master
serves two-step Sync/Follow_Up/Delay_Resp with Announce on the
ethernet port, IEEE 1588 over ethernet, end-to-end delay.

**JP1 must be in position B**: the 20 MHz VCXO reaches the FPGA on
the shield's A5 route, package pin D5, the clock-capable pin (the
schematic's A7/Z7 MRCC labels are swapped; position A lands on U18,
which is not clock-capable).  JP1 is a three-way solder bridge
closed between pads 1 and 2 as fabricated, which is position A:
rework it to pads 2-3.

**The fitted oscillator is a clipped-sine part**: Taitien
TXEAADSANF-20.000000, output code ``S``, about 1 Vpp into
10 kΩ‖10 pF, ±5 ppm pulling range over a 0.5 V to 2.5 V control
voltage.  An LVCMOS33 input needs a swing across its threshold, near
1.5 V with a 2.0 V minimum for a high: AC-couple the output and bias
it at mid-rail, or fit the CMOS-output variant ``TXEAADJANF``.  The
``rates`` instrument carries both the D5 (``vcxo``) and U18
(``vcxo_a``) routes, so the receiver side is checked from the host
without a scope.

**The MCP4726 A0 pin is tied to VDD** on the shield: the DAC answers
at 0x61, ``dac_address_c => 1``.

**The shield has no pull-up on the DAC I2C pair**: the Arty's header
pull-ups are switched in from the FPGA, package pins A14 (SCL) and
A13 (SDA), driven high by the design.

J4 is the 10 MHz reference SMA behind the FIN1019, not a PPS.  The
design drives the port in receiver direction with the raw VCXO
clock, so an external counter on J4 reads the oscillator directly;
``clock_measure.py freq-read`` reads such a counter over USBTMC.

Architecture
============

::

  VCXO 20 MHz (JP1-B, D5 SRCC) -> PLL x50/8 -> rtc clock 125 MHz
    clock_adjustable + capture files + discipline (all rtc domain):
      TIMEPULSE -> discipline_pps_source -> pi_servo -> one of:
        discipline_clock_driver -> increment (dac_discipline_c false)
        discipline_dac_driver -> MCP4726 -> VCXO (default)
      UART 9600 -> ubx_nav_timegps -> discipline_second_setter
      screen_text -> terminal_labels -> pmod_oled_rgb_driver on JA
      pps_ticker -> PPS_OUT SMA and GPS EXTINT (self-measurement)
      AUX SMA -> discipline_pps_source, measurement only -> panel
  100 MHz board clock: MII driver + shims, mac + ethernet,
      ptp_l2_master (announce on, clockClass 6 while GPS-locked,
      248 otherwise), SMI link monitor, VCXO DAC I2C (xo pins):
      one framed transactor shared by a one-shot initer (vref,
      power, midscale) and the value updater through an arbiter
  Sidebands cross stack -> rtc through
      timestamping_sideband_resync; nothing else carries time.

The receiver is auto-configured: a UBX CFG-MSG enabling NAV-TIMEGPS
at the navigation rate on UART1 is sent shortly after reset and
re-sent every eight seconds until frames flow.  Factory NMEA output
keeps running interleaved; the decoder resynchronizes over it.
"GPS locked" = valid week + time of week, reported accuracy under
tacc_max_ns_c, frames fresh; it gates the PPS discipline, the
second setter and the advertised clock class.

LEDs LD4..7: heartbeat, ethernet link, GPS locked, PPS.

Status screen
=============

A Pmod OLEDrgb (SSD1331, 96x64) on JA shows the grandmaster status as
a 16x8 text screen, rendered by ``nsl_dvi.terminal.terminal_labels``
from ``src/func/screen_text.vhd`` in the stack domain, every value
having already crossed for the panel::

  # LNK^ GPS* PPS*     a heart blinking on the local second, the link
                       as an up or down arrow, the GPS lock and the
                       receiver's pulse as a filled or hollow dot; the
                       pulse dot toggles on every pulse received, so
                       it freezes when they stop
  2026-09-08   UTC     date and time of day in UTC: the time base
  13:21:22  TAI+37     counts PTP seconds, the announced offset is
                       taken off; yellow until the receiver has
                       reported the leap second count
  PPS  -000012 ns      time base against the receiver's pulse
  AUX  -001193 ns      time base against the pulse on the AUX SMA
  SERVO +00332 ppb     servo correction, applied to the DAC
  TACC 000014 ns       receiver's accuracy estimate
  CLS 006 DAC 0835     announced clock class and DAC code

Link, GPS and class rows are green when good and red otherwise
(yellow for a holdover class); the PPS offset and the accuracy are
green within 100 ns, yellow within a microsecond, red beyond.  Signed
values saturate at their digit count.

Status
======

The project builds with Vivado 2022.2 (``gbs -t
gbs.builtin.vivado=vivado:2022.2 project build``), timing clean, and
locks on the board: with the receiver fixed, the second is set to
the PTP epoch on the first labelled pulse, the servo settles within a
minute and the PPS offset then sits on zero within the 8 ns time base
quantum (mean under a nanosecond, standard deviation about 8 ns, DAC
moving by a code or two).  An independent GPS reference (a LeoNTP)
fed to the AUX SMA reads a settled ``aux_offset`` of about -1.2 us
with 20 ns of jitter: the skew between the two receivers' pulses as
the board sees them through the same input path, the input latency
cancelling in ``aux_offset - pps_offset``.

``rtc_from_vcxo_c`` in fpga_io selects the time base source: the
VCXO through its PLL with DAC discipline, or the board oscillator
with increment steering.  The board oscillator is only a bring-up
fallback: its error (about 11 ppm on this board) exceeds both the
servo's ±8 ppm authority and the PPS source's 10 µs alignment
threshold, so that configuration realigns on every pulse and never
feeds the servo.  The reset of the whole design waits for the time
base PLL, so a missing VCXO clock freezes everything but the Gatecap
rack: a ``second`` stuck at zero on the panel with ``rtc`` at 0 Hz on
``rates`` is that condition.

Known rough edges: the ``gps`` analyzer's RLE capture returns only a
couple of lines whatever the time cap, so the UART and pulse-pair
views are not available yet; the PTP rung has not been exercised
from a host.

Bring-up ladder
===============

1. LD4 blinks (alive), LD5 on with a cable (link).
2. GPS antenna on J5, sky view; after fix, LD6 (locked).  Serial
   sniffing on the GPS pins shows NMEA at 9600 plus the binary
   NAV-TIMEGPS frames after the CFG-MSG went out.
3. PPS_OUT (J1) against the receiver's own pulse on a scope or
   Gatecap: sub-microsecond after alignment, tightening as the
   servo settles.  The same pulse feeds EXTINT: reading the
   receiver's event timestamps (UBX TIM-TM2) measures our boundary
   with the receiver's own timebase — the calibration channel for
   the constant resynchronizer latency.
4. PTP: a slave Arty (tests/ptp/two_nodes structure) or a Linux
   box: ``ptp4l -i <if> -s -m -2`` should list this grandmaster
   (clockClass 6, timeSource 0x20) and lock.

Debug frontend
==============

A Gatecap rack (``description.yaml``) rides the chip TAP:

* ``rates``: clock measurer against the 100 MHz board clock -- the
  disciplined 125 MHz time base (the servo at work), the raw 20 MHz
  VCXO, and both MII clocks.
* ``panel``: link, GPS lock, the running second, the receiver's
  accuracy estimate, the servo's correction in ppb, the last PPS
  offset seen by the servo, the time base at the last pulse on the
  AUX SMA (the time base values cross through a settled register)
  and the applied DAC code, plus a remote reset.
  Event counters count the receiver's pulse and the local one
  against wall-clock time, the receiver's bytes and decoded
  NAV-TIMEGPS frames, and the PPS discipline steps: pulse seen in
  the time base domain, boundary realigned, offset handed to the
  servo, second set, pulse on the AUX SMA.  The I2C pair levels are
  shown as statuses.
  ``dac_force_en``/``dac_force`` override the DAC code for slope
  calibration.
* ``i2c``: logic analyzer on the DAC bus, sampled on the PHY receive
  clock so a whole write fits the buffer; ``sigrok-cli -I vcd -P
  i2c:scl=scl:sda=sda`` decodes the dump.  The panel also counts the
  initer's and updater's frames and the transactor's responses.
* ``gps``: run-length encoded logic analyzer in the time base domain
  on the receiver's serial pair, its time pulse, the local pulse and
  the EXTINT feedback -- the whole discipline story on one capture,
  including whole UART bytes and a full second between pulses.

There is no ``gatecap`` binary: the rack is driven with ``acrobe
gatecap -r dig-<serial>/jtag/chain/0/bnoc_continuous_transport/gatecap
{info,rates,capture}``; the panel needs a Python script run with
``acrobe run`` (``Session`` from ``acrobe_plugin.gatecap.session``).

Note for Vivado: the raw VCXO clock also feeds a measurement
counter; if the router complains about the clock net reaching
fabric, a CLOCK_DEDICATED_ROUTE waiver on that path is harmless.

Pulse latency calibration
=========================

Two constants place the second boundary and the local pulse on the
receiver's pulse edge:

* ``pps_input_delay_ns_c``, taken off the time base sampled at the
  pulse: the input resynchronizer is five cycles of the time base
  clock (40 ns) plus pad and route.  It also places the PTP
  timestamps, so it is set from the pipeline and not trimmed on the
  pulse.
* ``pps_output_lead_ns_c``, how early the ticker fires before the
  boundary: two ticker registers and the output register (24 ns) plus
  the output buffer.

An independent reference pulse on the AUX SMA (J3) is timestamped by
the same input path and shown on the panel as ``aux_offset``, the
time base at that edge with the same delay taken off.  With the
input constant right, ``aux_offset`` reads the receiver's own offset
to that reference; the difference ``aux_offset - pps_offset`` is
that offset as the board sees it, and any error of the input
constant shows up as a difference to the same skew measured on a
scope between the two pulses.  The output lead is then trimmed on the
scope, PPS_OUT against the reference, in 8 ns steps.

DAC discipline
==============

The servo's ppb output steers the VCXO through the MCP4726 on the
shield's dedicated I2C pair (xo_sda/xo_scl); the RTC increment stays
nominal.  The oscillator's ±5 ppm pulling range makes
``dac_full_scale_ppb_c`` about 10000; the sign is a guess until
measured:

* ``dac_discipline_c => false`` falls back to the proven digital
  increment steering with the DAC parked at midscale — the safe
  first boot if the analog loop misbehaves.
* Watch ``dac`` and ``freq_ppb`` on the panel.  Both railing in the
  same direction means the tuning slope sign is wrong: set
  ``dac_invert_c``.
* Slope calibration: set ``dac_force_en`` and step ``dac_force`` on
  the panel, read the ``rtc`` line of the ``rates`` instrument (8 ppb
  per Hz at 125 MHz) at each code, fit; scale
  ``dac_full_scale_ppb_c`` so a code step predicts the observed
  frequency step.
