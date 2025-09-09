
AXI4-MM fifos
=============

Fifo blocks come in three flavors, for each of the four streams
(Address, Write data, Read data and Write response):

* Full fifo with one or two clock domains,

* Fifo slice, a.k.a. a skid buffer.  All output signals are
  registered.  This allows to break combinatorial paths This actually
  is a 2-deep fifo where pipelining can happen.

* A clock-domain-crossing module. This one only handles one beat at a
  time. This is mostly useful for low bandwidth streams.

There is one bus fifo component `axi4_mm_fifo`, where fifo depth and
number of clocks (one or two) can be specified.  Depending on fifo
depth and number of clocks, component will automatically instantiate
any of the three blocks above.  Fifo depth can be independently set
for the 5 channels.

This creates a fifo with various sizes for various channels in one
clock domain:

.. code:: vhdl

   fifo: nsl_amba.mm_fifo.axi4_mm_fifo
     generic map(
       config_c => config_c,
       clock_count_c => 1,
       aw_depth_c => 8,
       w_depth_c => 32,
       b_depth_c => 8,
       ar_depth_c => 8,
       r_depth_c => 32
       )
     port map(
       clock_i(0) => clock_i,
       reset_n_i => reset_n_i,
 
       slave_i => bus_s.m,
       slave_o => bus_s.s,
 
       master_o => bus2_s.m,
       master_i => bus2_s.s
       );

A clock-domain crossing fifo won't be much more complicated:

.. code:: vhdl

   fifo: nsl_amba.mm_fifo.axi4_mm_fifo
     generic map(
       config_c => config_c,
       clock_count_c => 2,
       aw_depth_c => 8,
       w_depth_c => 32,
       b_depth_c => 8,
       ar_depth_c => 8,
       r_depth_c => 32
       )
     port map(
       clock_i(0) => bus_s_clock_i,
       clock_i(1) => bus2_s_clock_i,
       reset_n_i => reset_n_i,
 
       slave_i => bus_s.m,
       slave_o => bus_s.s,
 
       master_o => bus2_s.m,
       master_i => bus2_s.s
       );
