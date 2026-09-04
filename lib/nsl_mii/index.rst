==================
 MII transceivers
==================

Network stack uses `bnoc committed <../nsl_bnoc/committed>`_ bus
framework as a transport. It allows for late cancellation of frame, in
order to be able to do worm-hole handling of packets with optional
late-cancellation.

MII library covers:

* 10/100 speed (`MII <mii>`_, `RMII <rmii>`_),

* 1G speed (`GMII <gmii>`_, `RGMII <rgmii>`_).

`Link status <link_monitor>`_ can be monitored either through SMI
(MDIO) interface, or through in-band status.

Drivers also expose SFD strobes for frame timestamping:
`timestamping <timestamping>`_ turns them into a per-frame identifier
sideband and a one-byte layer-1 pre-header tag, so consumers sample
their own time base (`nsl_time.capture <../nsl_time/index>`_) without
time ever entering the packet path.
