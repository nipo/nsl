10BASE-T without a Phy
======================

Receives ethernet frames on a Sipeed PMOD-Ethernet (HanRun HR911130A
magnetics, no Phy chip) plugged in J6, using only FPGA fabric and IOs.

The MAU sends normal link pulses, so a link partner with
autonegotiation enabled falls back to 10BASE-T half-duplex through
parallel detection.  Received frames go through FCS check; the head
of each frame is dumped on the UART at 115200 bauds, and a status
line is printed every second::

  01 80 c2 00 00 00 b4 fb e4 d1 a9 82 00 26 42 42 l=03c G
  =L1 P1 n=0669 g=0669

Frame lines carry the first 16 bytes, total length after FCS strip,
and FCS validity.  Status lines carry link state, detected pair
polarity, total received frame count and valid-FCS frame count.

Pin mapping was established with the ``ethernet_pairfinder`` example
and now lives in ``nsl_sipeed.pmod_ethernet``, which owns the pads and
the MAU behind them.
