
==============
BNOC Committed
==============

Committed is actually a subtype of `framed <../framed/>`_, only
difference resides in the last byte of every frame that, by
convention, holds a validity bit for the whole frame.  This allows for
last cancellation of a frame.

This package provides various tools:

* a `fifo <committed_fifo.vhd>`_, a `fifo slice <committed_fifo_slice.vhd>`_,

* a `filter <committed_filter.vhd>`_, that will wait for frame to be
  received and valid before letting it through. If failing, it will be
  internally dropped.

* a `funnel <committed_funnel.vhd>`_ and a `dispatcher <committed_dispatch.vhd>`_,

* a `sizer <committed_sizer.vhd>`_, computing frame size before
  letting it through,

* a `prefill buffer <committed_prefill_buffer.vhd>`_, ensuring a given
  count of words is available before forwarding, to avoid underflows,

* header `inserter <committed_header_inserter.vhd>`_ and `remover
  <committed_header_extractor.vhd>`_,

* a `statistics generator <committed_statistics.vhd>`_.
