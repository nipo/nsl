=================
Signal generators
=================

* `Frequency generator <frequency/>`_ can generate a binary signal
  with a given frequency from a clocked design.  This can be described
  as a fractional frequency divisor.

* `NCO <nco/>`_ is a numerically controlled oscillator, i.e. a block
  that outputs an oscillator waveform (sinus) with a given frequency.
  Frequency may be changed dynamically.  Backend implementation uses
  sinus (see below).

* `PWM <pwm/>`_ generates a PWM signal with selectable period, duty
  cycle and phase.

* `Sinus <sinus/>`_ generator gives sinus of input angle, pipelinable
  (one computed word per clock, with defined latency) or iterative.
  Backend implementation may be based on a look-up table or a Cordic
  core.

* `Trigonometry <trigonometry/>`_ gives sinus/cosinus of an input
  angle, pipelinable or iterative.
