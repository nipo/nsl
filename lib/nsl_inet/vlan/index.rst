======
 VLAN
======

802.1Q VLAN tagging.  Both components operate on the transparent
`mac <../mac/index>`_ boundary and return it: every pipe carries
``pre-header | DA | SA | ethertype | payload | status`` frames.

* the `demux <vlan_demux.vhd>`_ inspects the ethertype: frames
  carrying the 802.1Q TPID have TPID and TCI consumed and are routed
  on VID, one pipe per configured VID; frames without a tag are
  forwarded untouched to the untagged pipe; tagged frames with an
  unconfigured VID are dropped;

* the `mux <vlan_mux.vhd>`_ does the reverse, inserting TPID and TCI
  on frames coming from a VID pipe.

Because every pipe speaks the mac boundary format, each branch
composes freely:

* stack `ethernet <../ethernet/index>`_ host adaptation on a branch
  to terminate that VLAN (plus the untagged branch for native
  traffic), giving one ARP/IP stack per broadcast domain;

* stack another vlan demux for 802.1ad-style double tagging;

* wire a VID pipe pair straight to another port's `mac
  <../mac/index>`_ layer to build a transparent VLAN fan-out device,
  turning one tagged interface into a set of native ones with no
  possible traffic between the native ports.

Priority tagging is not supported: PCP and DEI are discarded on
receive and transmitted as zero.
