PCM IIR cascade
===============

``pcm_iir_cascade`` applies ``stage_count_c`` second-order sections to every
channel in each framed signed-PCM AXI4-Stream beat.  It stores independent
history for every channel and stage.  One multiplier is reused iteratively;
the block accepts no new frame until the previous frame has been emitted.

The flattened coefficient port contains, from its least-significant field,
``b0, b1, b2, a1, a2`` for stage 0, followed by the same fields for each next
stage.  Each field is signed two's complement with ``coefficient_width_c``
bits and ``coefficient_fraction_bits_c`` fractional bits.  A stored integer
``C`` therefore denotes ``C / 2**coefficient_fraction_bits_c``.

For channel ``c`` and section ``s`` the direct-form-I recurrence is::

  y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2]
                    - a1*y[n-1] - a2*y[n-2]

The accumulator and histories use signed fixed point with
``coefficient_fraction_bits_c`` fractional bits, ``sample_bits`` PCM integer
bits, and ``guard_bits_c`` additional integer bits.  Each product is truncated
to that format and saturated; every accumulation step is also saturated.  A
section output is truncated toward minus infinity to an integer PCM sample and
saturated to ``sample_bits`` before entering the next section and at output.
Thus low-pass, band-pass and high-pass behavior is solely a coefficient choice;
``b0=1`` with all other coefficients zero is identity.

All coefficients of a section are latched together when that section starts.
An update therefore takes effect at the next section invocation and existing
filter history remains continuous and defined.  Software should update all
fields while the stream is idle if one frame must use one coefficient bank.
Asserting ``flush_i`` deasserts both stream handshakes immediately; on the next
rising edge it discards an in-flight frame and clears all histories.  Hold it
through at least one rising edge after changing coefficients when a state-free
change is required.

The input beat's TLAST, TUSER (including channel sideband and packet flags),
TID, TDEST, TKEEP and TSTRB are retained exactly.  Only configured TDATA sample
bytes and TVALID are regenerated.

Latency is data dependent on backpressure and otherwise approximately
``channel_count * stage_count * 7`` processing clocks plus control clocks.
This architecture targets audio-rate streams and favors one shared multiplier
over frame-rate throughput.
