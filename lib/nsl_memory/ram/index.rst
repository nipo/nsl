==========
RAM blocks
==========

Various RAM blocks are available.

Single-port single word RAM
===========================

`ram_1p`_ is a small and easy RAM with one port, on every cycle with
``enable=1``, output is read from memory targetted by address, optionally,
memory at address can be written.

.. image:: ram_1p.png
   :width: 670 px

.. _ram_1p:

.. vhdl:autocomponent:: nsl_memory.ram.ram_1p

Single-port multiple-word RAM
=============================

`ram_1p_multi`_, is basically the same as
`ram_1p` but has a concept of words and write masks. Data interface
is a group of `data_word_count_c` each of width `word_size_c`. There
are `data_word_count_c` write enable inputs for
`data_word_count_c*word_size_c` input data bits.

.. _ram_1p_multi:

.. vhdl:autocomponent:: nsl_memory.ram.ram_1p_multi

Dual-port RAM, one write, one read
==================================

`ram_2p_r_w`_, is a little more complicated. It has two ports, one
write only, the other read only.  With generic ``registered_output_c``
set to ``false``, it has the same timing characteristics as `ram_1p`_.

Additionally, this module may have two clocks rather than one, one for
each port.

.. image:: ram_2p_r_w.png
   :width: 701 px

   "reg" and "base" lines refer to whether regsitered_output_c is
   enabled or not, respectively.

.. _ram_2p_r_w:

.. vhdl:autocomponent:: nsl_memory.ram.ram_2p_r_w

Dual-port, multi-word RAM
=========================

`ram_2p_homogeneous`_, like `ram_1p_multi`_, has concept of words with
discrete enables, but both ports may read and write.  Read timings
match those of `ram_1p_multi`_ and the same ``registered_output_c``
generic is available.  This module has one clock for each port.

.. _ram_2p_homogeneous:

.. vhdl:autocomponent:: nsl_memory.ram.ram_2p_homogeneous

General dual-port byte RAM
==========================

`ram_2p`_, is a byte-based ram where input aspect ratio and output
aspect ratio may not be the same.  This can act as a backing storage
for a width changing fifo.  This module has one clock for each port.

.. _ram_2p:

.. vhdl:autocomponent:: nsl_memory.ram.ram_2p
