JTAG continuous-transport demo platform
=======================================

A GHDL simulator that exposes both ends of a ``nsl_jtag.continuous_transport``
link as TCP sockets, for developing the host-side software driver.

Pipeline::

  host :4242 (ATE side)                         host :4243 (application side)
      |                                              |
  tcp_framed_gateway (HDLC)                     tcp_framed_gateway (HDLC)
      |                                              |
  framed_fifo x2                                framed_fifo x2
      |                                              |
  nsl_jtag.transactor.framed_ate  --JTAG-->  jtag_sim_tap  --(globals)-->
                                             continuous_transport_slave

Build
-----

::

  gbs -C demo/jtag_continuous_transport project build

This produces ``simulator.exe``. The build does *not* run it: the simulation
never terminates (it serves the two sockets), so launch it by hand::

  ./simulator.exe

It binds two TCP ports and runs forever; kill it when done.

Sockets
-------

- **:4242 -- ATE side.** Carries the JTAG transactor command/response stream,
  HDLC-framed. The driver speaks the ``nsl_jtag.transactor`` command protocol
  (``cmd_capture_ir``/``cmd_capture_dr``/``cmd_shift*``/``cmd_run`` ...): it
  selects the user IR, then shifts ``continuous_transport`` batches as DR
  shifts and reads the TDO back in the responses.
- **:4243 -- application side.** Carries the application byte stream,
  HDLC-framed. Whatever the driver pushes through the transport surfaces here;
  whatever a peer sends here comes back to the driver on TDO. Frame boundaries
  (HDLC) map to the transport's packet ``last``.

Both sockets use HDLC framing, matching the crobe ``tcp/.../pipe/hdlc/...``
convention.

Parameters the driver needs
---------------------------

- IDCODE ``0x87654321``; IDCODE instruction ``0x2`` (4-bit IR).
- USER0 instruction ``0x8`` selects the ``continuous_transport`` data register
  (``reg_id_c = 1``). Select it before shifting any batch.
- The wire format (preamble ``0x55``, SOF ``0xd5``, frame encoding, credit /
  TX budget / tx-level, alignment pad) is specified in
  ``lib/nsl_jtag/continuous_transport/continuous_transport.md``.
- The simulated TAP has a single device in the chain, so the upstream/downstream
  BYPASS latencies (U/D) are zero.
