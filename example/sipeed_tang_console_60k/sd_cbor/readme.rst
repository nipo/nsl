==================
 SD card over USB
==================

Puts the SD card socket of the board on its USB port: what arrives is
a stream of commands for the bus, and what leaves is the answers to
them.  Nothing in the gateware knows what a card is — the
identification sequence, the command set of whatever answers, and what
to do about an error all live on the host — so the same fabric serves
a card holding memory, an SDIO peripheral, or a card that misbehaves.

The commands are the ones ``nsl_sdio.cbor_transactor`` describes.

Framing
=======

One batch of commands is one frame, and one frame is one transfer,
which ends where a short packet ends it.  Nothing has to look for the
edges of anything, the bus below checks what it carries, and a host
that stops reading stops the device rather than losing what it sent.

A session that dies leaves the device holding whatever it was in the
middle of.  A bus reset is what takes it back to the start: the device
goes through enumeration again and what is behind the endpoints is
held in reset until it comes out the other side.  The host does this
whenever it opens the device.

Speed
=====

The USB side wants 60 MHz and a card wants a bus period that divides
into what it is clocked from, so each side has a clock of its own with
a pair of fifos between them.  The card side runs at 100 MHz, which a
quarter of is default speed and half of is high speed.

What comes off a card at 50 MHz over four lines, which carry 25 MB/s
between them:

===========  =========  =========  ========
blocks/read  in flight  measured   of a bus
===========  =========  =========  ========
1            1          1.2 MB/s   5%
64           1          17.0 MB/s  68%
64           2          20.9 MB/s  84%
256          2          23.2 MB/s  93%
1024         2          23.7 MB/s  95%
===========  =========  =========  ========

Three things stand between a bus and running full, and the table is
them in order.  A card asked for one block at a time spends more
looking for the next command than a block of data costs on the wire,
so blocks are asked for in runs.  A host that waits for one run before
asking for the next leaves the bus idle for a round trip, so the next
batch goes into the device while the one before it is still being
answered — two in the air is enough, and more buys nothing.  What is
left is what a block costs beyond its bytes: a start bit, a checksum
per line, an end bit, and the gap before the next one.

Going faster than 50 MHz means 1.8 V, and the socket of this board is
wired to 3.3 V with nothing in between, so 25 MB/s is as much as there
is to have here.

Writing
=======

Writing works, and the blocks come back as they went in, as long as
the bus stays under about twenty megahertz.  Above that a block comes
back with a byte or so of it wrong, once every few kilobytes.

What is wrong with it is worth writing down, because it is not what it
looks like.  A card checks what it is given and says so, and it says
the blocks were good: the checksum matches the bytes, and both are
wrong together.  So the bytes were already wrong here before they went
out.

They go wrong only when the bytes arrive more slowly than the bus
takes them, which above twenty megahertz is most of the time.  A card
cannot be held inside a block, so the only thing to do is take its
clock away until the next byte turns up, and that decision travels a
long way in one cycle: whether there is a byte, whether to stall,
whether the clock runs, whether to drive, and then the block's
checksum and the wires are worked out from what that settles on.  A
simulation has no time in it and has never shown this; two tests were
written for it and both pass.

So it is the one path in here that has to be taken apart before a
write is as fast as a read.  Until then, write with the bus slowed
down, and read at whatever a card takes.

Pins
====

The socket is the one on the board, wired straight to the fabric, and
the pads provide the pull-ups the command and data lines need.  The
card detect contact reads as an empty socket on this board whether or
not a card is in it; nothing waits on it, so a card answers all the
same.

The buttons of this board sit in the bank the socket is in and are
wired for a supply a card cannot take, so this takes its reset at
power-up instead of from one of them.

Running it
==========

Load it::

  openFPGALoader --ftdi-serial <board> sd_cbor.fs

then, from ``host/``::

  acrobe run walk.py [block ...]

which brings the card up, says what it is, and reads the blocks named
on the command line — the first one by default, where a formatted card
keeps its partition table.

The bitstream is built uncompressed: openFPGALoader does not read a
compressed one back out of this family.
