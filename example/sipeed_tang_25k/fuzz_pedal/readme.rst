============
 Fuzz pedal
============

A guitar fuzz box -- amplifier, saturator, amplifier, tone control,
amplifier -- running at 48828 frames a second on the board's own
oscillator.

Boards
======

====== ========================== ==========================
J4     Digilent Pmod I2S2         guitar in, amplifier out
J5     MuseLab iCESugar LCD 0.96" panel
J6     Sipeed Pmod BTN 4+4        keys
USB-A  control surface            knobs, optional
====== ========================== ==========================

The Pmod I2S2 jumpers stay where they leave the factory: the input
converter takes the word and bit clocks the board sends it, so both
converters run off the one master clock and no rate has to be
reconciled anywhere.

A mono instrument lands on the left of the stereo input jack, which
is the channel the chain takes.  What comes out is that one channel
on both sides of the output.

Knobs
=====

There are two ways to work them, and either may be used without the
other.

Keys K1 and K2 walk down and up the three knobs, following where the
keys sit on the board rather than where a row sits in the list: the
lower key moves further down.  K3 and K4 turn the knob whose row the
panel shows in white, the others being a dimmer blue.  Holding a key
runs it along.  The slide switches do nothing.

A control surface on the USB-A port turns all three at once, a knob
each, and needs no choosing.  Only one device is listened to -- the
one at 1500:0ec1 -- and only its first three rotations; its keys, its
knob presses and its fourth knob are read off the wire and ignored.
The bottom row of the panel says what is on the port: SEARCHING when
nothing has enumerated, the vendor and product of whatever has, in
green when it is the one whose knobs are wired up.

DRIVE
  Nothing to +48 dB, in steps of a decibel and a half, into the
  saturator.  This is the knob that makes the fuzz, and it does not
  make anything louder: the saturator hands back the same full scale
  however hard it is driven, so what the knob decides is how far past
  the threshold the signal goes and therefore how much of the
  waveform is flattened.  Two settings are comparable by ear without
  anything downstream having to undo the drive.

TONE
  All lowpass to all highpass.  The two filters are at 700 Hz and
  1500 Hz and the knob fades between them, which is the tone stack of
  the pedals this imitates: the middle of the travel is scooped
  rather than flat.

LEVEL
  -36 dB to +12 dB, on the way out, and the only place in the chain
  where hitting the rail is a surprise rather than the point.  The
  number is the gain of the whole output stage: a fixed recovery
  amplifier sits between the saturator and the tone control, and the
  knob is set to that much less.  At 0 dB a saturator output that has
  reached full scale leaves the box at full scale.

The panel also shows how loud the instrument is (IN, six decibels a
character, seventy two of them) and how far into the saturator it is
being driven (DRV, six decibels a character counted from full scale
up).  RATE is the frames a second actually delivered by the input
converter, and the last row counts frames lost either end, which
should stay at zero once the wire has started.  The done LED is lit
while the drive is pushing past what the saturator hands back.

USB
===

The host is ``nsl_usb.hid_host``, built with ``full_speed_c``, so it
takes the device at either speed: a device says which it is by which
line it pulls up, and the host reads that off the idle bus before it
says anything.  Full speed then costs it nothing but a faster clock,
a full-speed bus being a low-speed one with bits eight times shorter
and J on the other line.

The input report is seven bytes -- three of switch bitmap, then one
signed byte per knob of how far it turned since the last report --
which fits the eight a low-speed packet carries, so one poll brings a
whole report whichever speed it came at.  Polled every 8 ms.

The switch bitmap contains 20 button bits and four padding bits. The
four signed rotation bytes follow at offsets 3 through 6. Encoder
movement accumulates with five fractional bits: 32 counts make one
parameter step, and 1024 counts (one turn) span the 32-step range.
The accumulated position clamps at each end. Board keys still move a
whole parameter step. ``usb_rotation_fraction_bits_c`` in
``src/boundary.vhd`` sets this scaling.

The engine wants a 48 MHz clock, which is a PLL of its own and the
only thing in this design outside the 50 MHz domain.  Nothing crosses
between the two but reports, through a FIFO with a clock at each end,
which leaves the audio in one domain from converter to converter.

UART diagnostics
----------------

The UART sends a snapshot at 115200 baud, 8N1, approximately every
100 ms. For example::

  USB 1500:0ec1 DP1 DN0 FS E000 R79a P001 I1500:0ec1 Q5a C40000000 H05d0 D000000fe000000 K001a00

All numeric fields except the line levels are hexadecimal:

* ``DP`` / ``DN``: sampled bus levels; ``FS`` / ``LS``: detected speed.
* ``E``: protocol watchdog restarts; ``R``: packets with a valid PID,
  including NAKs. Both counters wrap at 4096.
* ``P``: microcode program counter. The listing from
  ``tests/usb_hid_host/dump`` maps these addresses to instructions.
* ``I``: identity registers, including while enumeration is incomplete.
* ``Q``: most recently received PID (``5a`` is NAK).
* ``C``: four bytes: EP0 maximum packet size, bytes left in the control
  read, descriptor offset, and receive count with the error flag in bit 7.
* ``H``: completed HID reports, wrapping at 65536.
* ``D``: the latest seven-byte report. ``fe`` in byte 3 above is a
  drive rotation of -2 encoder counts.
* ``K``: drive, tone and level positions, each from ``00`` to ``20``.

The Tang board keeps USB VBUS powered during FPGA reprogramming. A
controller power cycle requires unplugging it; the control surface
also takes about three seconds to select its mode before asserting
its USB pull-up.

Rate
====

48 kHz exactly is not reachable from this board: 50 MHz is a power of
two times a power of five, every multiple of 48 kHz has a three in
it, and no Gowin divider -- integer or eighths, feedback or output --
produces the 3125 that would be needed.  Nothing outside has a say in
the rate here, so the master clock is simply the main one divided by
four, at 12.5 MHz, and a frame is 256 of those.

Load into SRAM with::

  /opt/Gowin/current/Programmer/bin/programmer_cli --location <n> \
    --device GW5A-25A --operation_index 2 --frequency 15MHz \
    --fsFile <build>/fuzz_pedal.fs

``programmer_cli --scan-cables`` gives the location.  The debugger on
this board emulates an FT2232 whose MPSSE is always the first
interface, so the cable to use is the one reported as ``A/0/<n>``;
the ``A/1`` entry beside it is the other interface of the same chip
and is not a second board.
