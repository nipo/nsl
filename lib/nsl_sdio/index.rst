=========================
 SD, SDIO and MMC support
=========================

SD memory cards, SDIO peripherals and MMC parts share one bus: a
host-driven clock, a bidirectional command line, and one to eight
bidirectional data lines.  What they put on those wires is the same
too, bit for bit, and they only part company at the command set.  The
library follows that split rather than the card-type one.

* `sdio <sdio>`_: the wires, as seen from either end.

* `link <link>`_: the clock a host generates, the command tokens and
  answers that travel on CMD, and the data blocks that travel on DAT.
  Nothing there knows what a command means, which is what makes it the
  same for the three bus flavours.

* `cbor_transactor <cbor_transactor>`_: a host driven by a command
  stream, for a design where the card's command set lives in software
  rather than in the fabric.

* `testing <testing>`_: a card model to run a host against.

Above the link layer, a transaction is one command with an optional
data phase, and everything a fabric can be offered -- a command
stream, a register block, a block device port -- is an adapter on that
one interface.  What a given card type does with those transactions,
starting with its identification sequence, belongs above it again.

Board wiring
============

A host needs its command and data pads pulled up, whatever the board
holds them with: the bus counts on 10 to 100 kOhm, and the sockets
found on PMOD adapters are far weaker than that.

Recovery
========

A host that gives up on a transfer half way through leaves a card in a
state it alone knows.  A card sending a run of blocks sends until it
is told to stop, whatever the host does with what comes out, and one
waiting for the rest of a block it was promised waits.  Taking the
clock away only freezes that; it does not end it.

So a host that aborts anything has to put the bus back where it
started before it can use it again:

* clock at the rate identification runs at, over one data line, with
  everything released,

* the command that ends a run, whose answer does not matter: it is the
  one thing that reaches a card while it is busy sending, which is
  what the command line is separate for,

* the command that resets a card, which every card takes in every
  state,

* then identification from the beginning.

Anything shorter is a guess about a state nobody recorded.  A design
with the identification sequence in the fabric gets this for free, as
a step that fails puts the whole sequence back to the start; one
driven by software has to do it itself.

Speed
=====

A 3.3 V socket goes as far as high speed, which is 50 MHz and 25 MB/s
over four lines.  Everything past that is UHS, which signals at 1.8 V
and is only reachable through a bus that can be switched over, so it
needs a board whose socket sits on a switchable rail.

The bus clock is a divisor of the fabric clock, and where a host
samples its inputs inside a bus period is an input to the clock
driver.  A fabric clock at four times the bus clock or more leaves
that choice a real margin; twice the bus clock only works because a
card holds its output a little past the edge that ends it.
