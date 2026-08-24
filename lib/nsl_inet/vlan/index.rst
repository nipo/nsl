======
 VLAN
======

802.1Q VLAN tagging.  Both components operate on the transparent
`mac <../mac/index>`_ boundary and return it: every pipe carries
``pre-header | DA | SA | ethertype | payload | status`` frames, one
pipe per configured VID.

Untagged frames belong to the native VLAN, selected by generic:

* the `demux <vlan_demux.vhd>`_ routes frames on their 802.1Q tag,
  consuming TPID and TCI; untagged frames are merged, untouched, into
  the pipe whose VID matches the native VLAN.  Tagged frames with an
  unconfigured VID are dropped, and so are untagged frames when the
  native VID is not part of the configured list — which is the
  default, as VID 0 is reserved by 802.1Q;

* the `mux <vlan_mux.vhd>`_ does the reverse, inserting TPID and TCI
  on frames from every pipe but the native one, whose frames are
  forwarded untouched.

Because every pipe speaks the mac boundary format, each branch
composes freely:

* stack `ethernet <../ethernet/index>`_ host adaptation on a branch
  to terminate that VLAN, giving one ARP/IP stack per broadcast
  domain;

* stack another vlan demux for 802.1ad-style double tagging;

* wire a VID pipe pair straight to another port's `mac
  <../mac/index>`_ layer to build a transparent VLAN fan-out device,
  turning one tagged interface into a set of native ones with no
  possible traffic between the native ports.

Priority tagging is not supported: PCP and DEI are discarded on
receive and transmitted as zero.
