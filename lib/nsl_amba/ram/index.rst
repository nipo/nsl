======
 RAMs
======

This package provides an AXI4-MM and an APB RAM model. AXI4-MM model
is actually implemented in two variants: a simple one when AXI is
using the lite subset, and a full pipelined variant when the bus
supports bursts.

This creates a one kilobyte AXI RAM:

.. code:: vhdl

   constant config_c : config_t := config(address_width => 32,
                                          data_bus_width => 32,
                                          max_length => 16,
                                          burst => true);
   signal bus_s: bus_t;

   one_kb_ram: nsl_amba.ram.axi4_mm_ram
     generic map(
       config_c => config_c,
       byte_size_l2_c => 10
       )
     port map(
       clock_i => clock_s,
       reset_n_i => reset_n_s,
 
       axi_i => bus_s.m,
       axi_o => bus_s.s
       );
