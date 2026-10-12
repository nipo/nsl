===========================
 PTP slave over 10BASE-T
===========================

Goal
====

PTP ordinary clock, slave only, on the Tang Console 60k with a Sipeed
PMOD-Ethernet in J6 (HanRun magnetics, no Phy: the MAU lives in the
fabric).  IEEE 1588 over ethernet, end-to-end delay, two-step.  It
follows the first master heard in its domain, typically the
``digilent_arty_a7/ptp_gm`` grandmaster, disciplines a local time
base by steering its increment, outputs a pulse per second and shows
its state on an LCD.

Peripherals:

* PMOD-Ethernet in J6 (``j6_pmod_ethernet.cst``, same pinout as
  ``ethernet_10baset_inet``),
* icesugar PMOD-LCD-096 (ST7735, 160x80) in J7,
* PPS on A21, a pin of the SDRAM header (``../pinout/pps_a21.cst``),
* done LED: ethernet link; ready LED: PTP locked,
* USB2 connector, at full speed: Gatecap rack (``../pinout/usb_fs.cst``).

Architecture
============

::

  50 MHz board clock (core) -> PLL -> 100 MHz (line)
                                     -> 60 MHz (USB)

  line domain, 100 MHz:
    pmod_ethernet_axi4_stream --rx_sfd--> rx_tagger -> rx capture file
                              <-tx_sfd--- tx_strober -> tx capture file
                     prefill(12) <- tx_strober
    clock_adjustable <- discipline_clock_driver (increment)
                     <- discipline_step_applier (steps)
    pps_ticker -> stretch, gated by lock -> PPS (A21)

  dual-clock stream fifos, both directions

  core domain, 50 MHz:
    fifo_clean -> mac receiver -> ethernet layer (0x88F7,
      01:1B:19:00:00:00) <-> ptp_l2_slave -> mac transmitter
    ptp_l2_slave -> asymmetry correction -> discipline_pi_servo
    screen_text -> terminal_labels_colormap -> palette_expander
      -> pmod_lcd_096_driver (J7)
    Gatecap observer

The MAU strobes the start of frame delimiter of every frame it sends
and receives, in the line domain.  The time base runs in the same
domain, so the strobes sample it directly into the capture register
files, with no resynchronizer latency to calibrate.

On receive, the tagger inserts the capture register index in front of
each frame; the index travels with the frame through the domain
crossing to the protocol engine, which reads the capture back from
the core domain.  The capture file has sixteen entries: the error
filter holds a whole frame before the engine claims its index.

On transmit, the engine prepends a tag block asking for a capture in
register ``ptp_tx_tag_id_c``.  The strober sits before the prefill
buffer, so its tag queue covers every frame between it and the MAU,
and pairs each SFD strobe with its frame in order.  Completion
crosses to the core domain through ``timestamping_sideband_resync``,
which only signals once the capture register is written; the register
itself is read across domains, stable long before it is read.

Frequency corrections and steps cross to the line domain inside
``discipline_clock_driver`` and ``discipline_step_applier``.  The
increment is a ``ufixed(4 downto -26)``: 1.5 ppb quantum at the
10 ns nominal increment.

Lock state crosses to the line domain through a synchronizer, gating
the PPS output.  The time base second crosses to the core domain
through a settled register, for display.

Asymmetry
---------

Delay request-response assumes both directions take the same time.
Any difference ``a`` (master-to-slave minus slave-to-master, as seen
by the timestamps: cable, both ends' timestamp latencies, the MAU's
receive bit recovery against its transmit SFD point) biases the
measured offset by ``a/2``.  The ``asymmetry_ns_c`` generic of
``boundary`` takes ``a``; half of it is taken off the offset before
the servo, and on screen.  To calibrate, compare the master's and
the slave's PPS on a scope: a slave pulse lagging by ``d`` calls for
``asymmetry_ns_c`` increased by ``2 d``.

Expected precision
------------------

The MAU recovers bits from the line oversampled at 100 MHz: receive
timestamps carry about ±10 to 20 ns of jitter, transmit timestamps
one cycle.  On top of the 10 ns time base quantum, expect a settled
offset spread of a few tens of nanoseconds around a fixed asymmetry
to calibrate.

Timescale
---------

The time base counts PTP seconds (TAI, 1970 epoch).  Announce
messages are not parsed: the current UTC offset is not learned from
the master.  ``display_utc_c`` subtracts a fixed ``utc_offset_c``
(default 37 s) for display only; the screen says which timescale it
shows.

Status screen
=============

::

  # LNK^ PTP*     PTP L2 SLAVE   a heart blinking on the local
                                 second, link as an up or down arrow,
                                 lock as a filled or hollow dot
  2026-10-12  18:40:13  TAI      date and time of the time base,
                                 cyan when locked, yellow otherwise
  OFFSET +0000000c ns            last offset handed to the servo,
                                 local minus master, asymmetry
                                 corrected
  DELAY  +0000008f ns            mean path delay
  FREQ   +00014c ppb             servo correction
  SYNC 04d2  STEP 0001           offsets measured, steps applied
  RX   162e  TX   04d2           frames from and to the MAU
  ASYM   0 ns                    configured asymmetry

The offset is green within 100 ns, yellow within a microsecond, red
beyond or while unlocked.  Values other than the date are
hexadecimal, signed ones as sign and magnitude: decimal conversion of
the wide ones does not fit a core clock cycle.

Status
======

Builds with Gowin, timing met on all three clocks with little margin
on the line clock (100 MHz).  About 24% of the logic.

On hardware, against ``example/digilent_arty_a7/ptp_gm``: the slave
locks and the displayed offset oscillates around zero.  With both
ends on an ordinary switch, the master at 100 Mbit/s and this slave
at 10 Mbit/s, the slave's PPS leads the master's by about 17 us.
That is the switch, not the timestamps: it stores a frame before
forwarding it, and a 64-byte frame takes 51.2 us to receive at
10 Mbit/s against 5.12 us at 100 Mbit/s, so the two directions of
the path differ by about 40 us, half of which shows as offset.
``asymmetry_ns_c`` can take it out for a given switch.

The gatecap rack enumerates from a Linux host, not from macOS.

Phase 2: Announce parsing (best master selection beyond "first heard",
UTC offset from the master).

Bring-up ladder
===============

1. Done LED with a cable: link (as in ``ethernet_10baset_inet``).
2. ``RX`` counting with a master on the segment; ``TX`` counting
   at the delay request rate once Syncs are heard.
3. ``SYNC`` counting, one ``STEP`` at first, then the offset
   converging and the ready LED on.
4. PPS on A21 against the master's on a scope; calibrate
   ``asymmetry_ns_c``.

Build::

  gbs project build

Debug frontend
==============

A Gatecap rack (``description.yaml``) is a Full Speed USB device on
the board's USB2 connector, on a 60 MHz clock from the same PLL.  A host
enumerates it under a name derived from the rack's contents::

  acrobe info enumerate

and reaches it as ``gatecap-XXXXXXXX/gatecap``:

* ``line``: logic analyzer on the raw line, in the line domain, as in
  ``ethernet_10baset_inet``.
* ``panel``: link, lock, time base second, offset, path delay,
  frequency correction, sync and step counts, frame counters, and
  transmit timestamps delivered to the engine (should follow ``TX``
  minus nothing: every frame the slave sends is a delay request).

``status.py`` dumps the panel::

  acrobe run status.py gatecap-XXXXXXXX/gatecap

``timing.sdc`` constrains the clock nets behind the buffer and the
PLL and declares them asynchronous; without it the tool assumes a
default rate and this stack silently emits corrupted headers.
