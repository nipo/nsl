==========
Better HDL
==========

Purpose of this set of rules is to get better HDL code to serve three
main purposes:

* Improve synthesizability of code, to ease optimization process,

* Enhance readability,

* Improve debuggability.

Avoiding std_logic
==================

`std_logic(_vector)` and `std_ulogic(_vector)` only differ by one
feature: resolution.

Resolution is the language term for managing multiple drivers on one
signal.

In VHDL, if one signal is assigned from multiple sources, this is not
an error if signal type provides a resolution function. std_logic is
resolved, and standard package manages the merging of weak values `W`,
`L`, `H`, `Z`, `-` with strong values `U`, `0`, `1` yielding `X` in
case of conflict.

On the other hand, `std_ulogic` is unresolved. It can hold the 9 values
above, but triggers a fatal error in case there are multiple
drivers. This can be determined statically at elaboration. Moreover,
simulation is expected to be faster as simulation engine does not have
to care about resolution at all.

There is still one place where `std_logic` makes sense, this is for
inferring tri-states from ‘Z’ state on `inout` pin ports. This should
only happen in topcell, as we defined before that bi-directional buses
should use in/out/enable for entities.

`std_logic` and `std_ulogic` are type compatible without cast.
`std_logic_vector` and `std_ulogic_vector` require a simple type cast.

Avoiding inout ports
====================

If an input/output bus is to be created on an entity port map, there
should be `_i`, `_o` and `_oe_o` ports. Inout ports should be
avoided. There are multiple reasons, for instance:

* `std_ulogic` is preferred,

* Simulation may prefer to check unidirectional vectors and enable
  value,

* in an actual implementation, we may have to forward enable signal to
  some external driver chip that implements the tri-state.

Using standard libraries
========================

`ieee.std_logic_unsigned`, `ieee.std_logic_misc` and
`ieee.std_logic_arith` are (despite their names),
synopsys-specific. They  never got validated by IEEE.

We should only use ieee.numeric_std.

Relevant patterns:

from `std_(u)logic_vector` to `integer`::

  signal a : natural range 0 to 255;
  signal b : std_ulogic_vector(7 downto 0);
  a <= to_integer(unsigned(b));

from `integer` to `std_(u)logic_vector`::

  signal a : std_ulogic_vector(7 downto 0);
  signal b : natural range 0 to 255;
  a <= std_ulogic_vector(to_unsigned(b, 8));

Or even better::

  a <= std_ulogic_vector(to_unsigned(b, a’length));

Arithmetic operators are defined on `signed` and `unsigned` data
types, even with naturals, e.g.::

  signal a, b : unsigned(7 downto 0);
  a <= b + 1; -- valid code.

Optimizing counter
==================

Often, we have a counter for some shift register or some cycle
counting. Using `natural`, `positive` or `integer` with `range`
specification rather than `unsigned` may yield better results as
synthesizer will be responsible for selecting relevant encoding of
value.

When using integers, having counters that roll over on overflow may
not be critical. Use `mod` operator accordingly.

When there is a counter to count to a parametric number, it may be
better to write counter as a downcounter as termination condition will
always be comparison to `0`. This yields smaller implementation than a
comparator between two registers. (Exceptions: if backend fabric has
some numeric comparators, or if a difference between the two values is
computed anyway).

Letting the synthesizer and optimizer do their jobs
===================================================

Use dont care value `-` everywhere possible in
`std_(u)logic(_vector)`. This has two benefic side effects:

* Tools will be able to perform simplification driving logic for
  signal with dontcares,

* Simulation traces will carry the “dontcare” values, and we’ll be
  able to distinguish cycles where there is not useful data more
  easily.

Sometimes, signals are grouped together and there is a global enable
for the group. A typical example is AXI-Stream. If tvalid is not
asserted, tlast, tdata, and all other master-to-slave signals are not
meaningful.

When we write code that generates AXI-Stream outputs for an entity, we
should try to tell the synthesizer all the places where we do not
actually care about the signal value.

.. TODO

.. In the above picture, understanding the actual behavior of shift
.. register is easier with a (others => ‘-’) initialization. Synthesized
.. version will probably takes useless values from some MUX input.

Component forward declaration
=============================

Components should be declared in a package. Package is used as a
header in C.

Architecture should never have any component declaration in
declarative part.

Components should rely on packages. Instanciations should always use
component instantiation variant::

  label: [component] library.package.component_name

and never the entity instantiation variant::

  label: entity library.entity_name

The former is better as parser is able to do type-checking of generic
and port map before elaboration. Moreover, we can then use assignation
of array or record elements one by one, and perform type conversion on
output ports. i.e.::

  label: entity library.entity_name
  port map(
    std_ulogic_vector(unsigned_data_o) => some_suv_signal, -- output port type cast
    unsigned_data_i => unsigned(other_suv_signal), -- input port type cast
    some_array(0) => some_signal, -- array assignation per element
    some_array(1) => other_signal,
    some_record.field_a => foo, -- record assignation per element
    some_record.field_b => bar
    );

Using records
=============

Records are just another data type. They can group signals of various
types logically. They can be used as ports, they can be used in
arrays.

When using ports with records, we should use one record for each
direction. Let’s take an example with AXI-Lite::

  library ieee;
  use ieee.std_logic_1164.all;

  package axi4_lite is

    type a32_d32_ms is
    record
      awaddr : std_ulogic_vector(31 downto 0);
      awvalid : std_ulogic;

      wdata : std_ulogic_vector(31 downto 0);
      wstrb : std_ulogic_vector(3 downto 0);
      wvalid : std_ulogic;

      bready : std_ulogic;

      araddr : std_ulogic_vector(31 downto 0);
      arvalid : std_ulogic;

      rready : std_ulogic;
    end record;

    type a32_d32_sm is
    record
      awready : std_ulogic;

      wready : std_ulogic;

      bvalid : std_ulogic;
      bresp : std_ulogic_vector(1 downto 0);

      arready : std_ulogic;

      rvalid : std_ulogic;
      rresp : std_ulogic_vector(1 downto 0);
      rdata : std_ulogic_vector(31 downto 0);
    end record;

    type a32_d32 is
    record
      ms: a32_d32_ms;
      sm: a32_d32_sm;
    end record;

  end package;

Then an entity can use the records for ports::

  entity axi_i2c_dp_ram is
    generic (
      [...]
      );
    port (
      [...]
      axi_ms_i   : in  signalling.axi4_lite.a32_d32_ms;
      axi_sm_o   : out signalling.axi4_lite.a32_d32_sm
      );
  end entity;

Then instantiation is reduced to::

  signal axi_mem : signalling.axi4_lite.a32_d32;

  [...]

  dpram: nsl.axi_i2c.axi_i2c_dpram
    [...]
    port map(
      [...]
      axi_ms_i => axi_mem.ms,
      axi_sm_o => axi_mem.sm,
      [...]
      );
