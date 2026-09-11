
==============
 HDMI encoder
==============

HDMI is a superset of DVI. As such, NSL's HDMI implementation relies
on NSL's `DVI library`_.

`HDMI-specific`_ part also handles data island encoding.

Video mode timings are the same for both, and live in `nsl_dvi.mode
<../nsl_dvi/mode/>`_; `mode <mode/>`_ is the name HDMI users know
them by.


.. _DVI library: ../nsl_dvi/
.. _HDMI-specific: hdmi/
