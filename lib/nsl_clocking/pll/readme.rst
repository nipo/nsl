====
PLLs
====

Rationale
=========

Vendor clocking resources usually offer PLLs but they are quite
cumbersome to use most of the time because:

* feedback path is vendor specific and depends on the chip lineup,

* VCO locking range is chip-specific,

* There are various competing blocks with different interface for
  the same service,

* There are some arbitrary offsets and encodings in dividors that
  are not obvious from the port and generic names.

This package gives a simple interface for simple case: one input clock
of fixed frequency and one output clock of fixed frequency. This is
the minimal service every PLL allows to implement.

VCO parameters and PLL implementation are taken care of automatically.

For other instantiation cases (multiple outputs, phase shifts, etc),
user should fallback to vendor libraries as there is no common
feature.

Usage
=====

General PLL component is defined as::

  component pll_basic
    generic(
      input_hz_c  : natural;
      output_hz_c : natural;
      hw_variant_c : string := ""
      );
    port(
      clock_i    : in  std_ulogic;
      clock_o    : out std_ulogic;

      reset_n_i  : in  std_ulogic;
      locked_o   : out std_ulogic
      );
  end component;

Most of the time, just giving it input frequency and desired output
frequency will allow the implementation to find a matching set of
parameters for VCO, pre-divisor, post-divisor, PFD bandwidth settings
and other parameters.

Supported backends include:

* Gowin (GW1N / GW2A),
* Lattice iCE40,
* Lattice MachXO2,
* Xilinx Series6 and Series7,
* Simulation

Sometimes, some backend-specific parameters, including selecting
non-default implementation (like selecting between PLL and MMCM on
Xilinx parts, for instance), may be passed through `hw_variant_c`
parameter. See `package <pll.pkg.vhd>`_ comments for more info.