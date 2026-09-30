=========================
 Bus transaction loggers
=========================

AXI4-MM logger
==============

:vhdl:component:`axi4_mm_logger <nsl_amba.mm_logger.axi4_mm_logger>`
is a passive monitor of one AXI4-MM bus.  It records every handshake of
every channel, with a timestamp, into memories readable over APB.  It
never drives the observed bus.

Several loggers can share one free-running ``timestamp_i`` counter to
correlate traffic on different buses of the same clock.

Recording
---------

Each channel (AW=0, W=1, B=2, AR=3, R=4) has its own memory of
``2**depth_l2_c`` entries, written at most once a cycle, so handshakes
of all channels in the same cycle are all kept.  While ``CTRL.enable``
is set, each valid and ready cycle of a channel appends an entry.
Once a channel's memory is full, further handshakes of this channel
are dropped and set its overflow flag.

An entry is four little-endian 32-bit words, word 0 at the lowest
address:

======= =============== ============================================
Channel Word            Content
======= =============== ============================================
all     0               ``timestamp_i`` during the handshake cycle
AW, AR  1               ``addr[31:0]``
AW, AR  2               ``id[15:0] | len_m1 << 16 | size_l2 << 24 |
                        burst << 27 | lock << 29``
AW, AR  3               ``cache | prot << 4 | qos << 8 |
                        region << 12 | stall << 24``
W       1               data bytes 0 to 3 (lane 0 in bits 7:0)
W       2               data bytes 4 to 7 (0 on a 32-bit bus)
W       3               ``strb[7:0] | last << 8 | stall << 24``
B       1               ``id[15:0] | resp << 16``
B       2               0
B       3               ``stall << 24``
R       1               data bytes 0 to 3
R       2               data bytes 4 to 7
R       3               ``id[15:0] | resp << 16 | last << 18 |
                        stall << 24``
======= =============== ============================================

``stall`` is the count of cycles the channel's valid was asserted
without ready before the handshake, saturated at 255.  For B and R, it
measures the backpressure of the master.

Fields are extracted with the ``nsl_amba.axi4_mm`` accessors: fields
absent from the configuration read 0, except size, burst and last,
which read their implied value.  Data buses wider than 64 bits are
rejected at elaboration.

Register map
------------

APB, 32-bit data, same clock as the observed bus.  Reads take one wait
state.

================================== =========== =========================================
Offset                             Register    Content
================================== =========== =========================================
0x000                              CTRL        bit 0: enable (reset 0), bit 1: clear
                                               (write 1 to reset counts and overflow
                                               flags, reads 0)
0x004                              STATUS      bits 4:0: overflow flag per channel
0x008                              TIMESTAMP   ``timestamp_i`` now
0x00c                              CONFIG      ``depth_l2_c`` [4:0], data bus width
                                               log2 bytes [11:8], ID width [23:16]
0x010 + 4 * c                      COUNT(c)    entries of channel c, 0 to
                                               ``2**depth_l2_c``
(c + 1) * 2**(depth_l2_c + 4)      entries     entry i of channel c at + 16 * i
================================== =========== =========================================

Other offsets read 0.  Writes other than to CTRL are ignored.  Offset
bits above ``depth_l2_c + 6`` are ignored.

A typical capture sequence is: write ``CTRL = 3`` (clear and enable),
run the traffic, write ``CTRL = 0``, read ``STATUS`` and the counts,
then read entries.

Implementation
--------------

Every channel memory is a ``nsl_memory.ram.ram_auto`` of 128-bit words
(block RAM with the default depth).  A handshake is registered in the
cycle it happens and written to memory the cycle after.
