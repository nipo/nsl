===============
 SD card probe
===============

Reads the first block of an SD card on a Sipeed PMOD-TF-Card in J4,
over and over, and spells it out on the serial port at 115200 8N1.

A round puts out one line saying what the bus looks like, then, if a
card answered, its identification, its specific data, the count of
blocks it holds, and the block itself, sixteen bytes to a line,
followed by a byte saying how the read went.

While no card has answered, every command the identification sequence
sends is put out instead, two bytes to a line: the index of the
command, and what came of it (``00`` answered, ``01`` nothing came
back, ``02`` bad checksum, ``03`` bad framing).

The line that opens a round is one byte:

===  =========================================================
bit  meaning
===  =========================================================
0    card detect pin of the socket, low while a card is in
1    write protect pin, which the board ties high
2    what the command line idles at
3    what the first data line idles at
4    a card answered the whole identification sequence
5    the command line was seen driven low since the last round
6    the clock was seen low since the last round
7    the clock was seen high since the last round
===  =========================================================

The three bits at the top are what tells a bus nobody answers on from
one nothing goes out on, and the two at the bottom say whether a
socket holds anything at all.  ``ef`` is a host talking to an empty
socket, ``ee`` one talking to a card that says nothing back, and
``fe`` a card that answered the whole sequence.

The serial port is far slower than the bus and nothing buffers a
block, so the card's clock is taken away between bytes and given back.
That is what a host on this bus does when the fabric cannot keep up,
and a block coming out whole is what says it works.
