=============
 Stream VLAN
=============

802.1Q VLAN tagging for the AXI4-Stream suite, the counterpart of the
bnoc `vlan <../vlan/index>`_ package.  Every component operates on the
mac side stream of `stream_mac <../stream_mac/index>`_ and returns it:
one pipe per configured VID, each carrying ``forwarded blocks | frame
block | payload`` packets with the reject flag of `stream
<../stream/index>`_ on their last beat.

* ``stream_vlan_demux`` routes frames on their 802.1Q tag, removing
  TPID and TCI; untagged frames go, untouched, to the pipe whose VID
  matches the native VLAN.  Tagged frames with an unconfigured VID are
  dropped, and so are untagged frames when the native VID is not part
  of the configured list — which is the default, as VID 0 is reserved
  by 802.1Q;

* ``stream_vlan_mux`` does the reverse, inserting TPID and TCI on
  frames from every pipe but the native one;

* ``stream_vlan_path_router`` bundles both with a mac receiver and
  transmitter on a tagged layer-1 link, optionally re-adding an FCS on
  every pipe (``routed_has_fcs_c``) so a layer-1 interface can sit
  directly on it.

The tag is 4 bytes long, a whole count of beats at every supported
width.  The ethernet frame block front padding is therefore the same
with or without a tag, and the payload starts on a beat boundary in
both cases: tag insertion and removal only rewrite the frame block,
the payload flows untouched.  Both directions are built on the
``nsl_amba`` stream router, one stage per header geometry:

* the demux peels the untagged header and dispatches on the
  ethertype, untagged frames to the native pipe, tagged ones to a
  second stage peeling the tagged header, looking the VID up and
  emitting the header without its tag.  The first stage only exists
  when the native VID is configured;

* the mux peels the untagged header of the tagged pipes and emits it
  with the tag of the source pipe; the native pipe joins the router
  output through a funnel.

Untagged frames and frames tagged with the native VID take distinct
paths in the demux and may be reordered relative to each other on the
native pipe.

Priority tagging is not supported: PCP and DEI are discarded on
receive and transmitted as zero.
