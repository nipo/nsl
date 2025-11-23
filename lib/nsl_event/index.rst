==================
 Eventing Library
==================

Eventing library exposes periodic (most of the time) signals that are
meant to be used as digital division of a reference clock.

Ticker framework can

* generate local periodic ticks (`integer
  <tick/tick_generator_integer.vhd>`_) and `fractional
  <tick/tick_generator_frac.vhd>`_,

* do sampling from an external (oversampled) `reference
  <tick/tick_extractor.vhd>`_,

* do `division <tick/tick_divisor.vhd>`_, `power-of-two multiplication <tick/tick_scaler_l2.vhd>`_ or `general scaling <tick/tick_pll.vhd>`_,

* `measure <tick/tick_measurer.vhd>`_ tick period.

Making a tick cross a domain is performed by `interdomain_tick
<../nsl_clocking/interdomain/interdomain_tick.vhd>`_ module in
`clocking <../nsl_clocking>`_ library.

Ticks are providing the base interface for PPS signaling in the `time
<../nsl_time#readme>`_ library.
