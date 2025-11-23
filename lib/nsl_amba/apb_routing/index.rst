=============
 APB routing
=============

APB dispatch is a module responsible for taking one command from an
APB slave port (connected to a master) and generating a number of
master ports (connected to slaves) where each has a disjoint subset of
the memory region.

In the following example, there are two slaves. The way the routing
table is encoded will synthesize a decoder such than only the bits 12
to 15 will be used.  This makes the decoder trivial (one LUT4 per
slave):

.. code:: vhdl

   use nsl_amba.address.all;
   use nsl_amba.apb.all;

   constant config_c : config_t := config(address_width => 32,
                                          data_bus_width => 32);
   signal bus_s, slave0_s, slave1_s: bus_t;

   -- ...

   router: nsl_amba.apb_routing.apb_dispatch
     generic map(
       config_c => config_c,
       routing_table_c => routing_table(config_c.address_width,
          "x----0000/20",
          "x----1000/20")
       )
     port map(
       clock_i => clock_s,
       reset_n_i => reset_n_s,
 
       in_i => bus_s.m,
       in_o => bus_s.s,
 
       out_o(0) => slave0_s.m,
       out_o(1) => slave1_s.m,
       out_i(0) => slave0_s.s,
       out_i(1) => slave1_s.s
       );
