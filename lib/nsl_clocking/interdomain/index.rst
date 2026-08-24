================================
 Interdomain clocking utilities
================================

Crossing a counter from one clock domain to another is done through
gray coding, as implemented by :vhdl:component:`interdomain_counter
<nsl_clocking.interdomain.interdomain_counter>`. This is only safe as
long as the crossed value moves by at most one step per input clock
cycle.

:vhdl:component:`interdomain_publish_counter
<nsl_clocking.interdomain.interdomain_publish_counter>` crosses values
that may jump by arbitrary amounts. It chases the target value at one
step per input clock cycle and crosses the chased value. Output
therefore lags behind the target, never leads it, and converges as
soon as the target rests.
