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

This package gives two entry points:

* `pll_basic`, a simple interface for the simple case: one input clock
  of fixed frequency and one output clock of fixed frequency. This is
  the minimal service every PLL allows to implement,

* `pll_multi`, for one input clock and multiple output clocks, with
  optional per-output rate tolerance, fractional division and phase
  offset.

VCO parameters and PLL implementation are taken care of automatically.

Basic usage
===========

General PLL component is defined as::

  component pll_basic
    generic(
      input_hz_c  : natural;
      output_hz_c : natural
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

Rates are all `pll_basic` states. Choices a rate does not express --
which pin type the reference comes from, which of several competing
blocks to use, which clock network an output drives -- are reachable
through `pll_multi` only, see below.

Multi-output usage
==================

`pll_multi` takes a `pll_config_t` record built with the `pll_config`
and `pll_output` helpers::

  constant cfg_c : pll_config_t := pll_config(
    input_hz => 27_000_000,
    o0 => pll_output(150_000_000),
    o1 => pll_output(75_000_000));

  ...

  inst: nsl_clocking.pll.pll_multi
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      clock_o => clocks_s,
      reset_n_i => reset_n_s,
      locked_o => locked_s
      );

Requested output rates are exact by default: elaboration fails when no
exact realization exists. `pll_output` optionally takes a
`tolerance_ppm` allowance, an `allow_fractional` opt-in for fractional
divisors, and a `phase` offset as a fraction of the output cycle.

Named choices
-------------

Blocks offer choices no divisor expresses. They are named by backend
functions turning a string into an opaque integer::

  constant cfg_c : pll_config_t := pll_config(
    input_hz => 12_000_000,
    o0 => pll_output(60_000_000,
                     routing => pll_routing_id("GLOBAL")),
    reference_input => pll_reference_id("CORE"),
    implementation => pll_implementation_id("MMCM"));

* `pll_reference_id` names the pin type the input clock comes from.
  On iCE40 it picks the primitive: `PAD` (the default) is
  `SB_PLL40_PAD`, whose `clock_i` must be the package pin itself,
  `CORE` is `SB_PLL40_CORE`, fed from fabric.

* `pll_implementation_id` names which block to use when the target has
  several: `PLL` or `MMCM` on Series-7, `PLL` or `DCM` on Spartan-6.
  It reaches the topology factory, since competing blocks have their
  own divisors and frequency windows.

* `pll_routing_id` names the clock network an output drives, per
  output. On iCE40, `GLOBAL` (the default) or `CORE`; on Gowin,
  `GLOBAL` or `NONE`, the latter leaving an output as it comes out of
  the block, which is what the reference of a second PLL wants.

The integer is opaque and backend-specific, so the generic types carry
the choice without knowing anything about it. Zero is always the
backend's default, hence a config naming nothing is portable across
targets. Each backend defines its own vocabulary and fails elaboration
on a name it does not have, so a name meant for another target is
caught where it is written.

Phase
-----

`pll_output` takes a `phase`, a fraction of the output's own cycle by
which it is delayed relative to the outputs that state none::

  o1 => pll_output(10_000_000, phase => (num => 1, den => 8))

What a block can hit depends on how it shifts. GW5A's PLLA moves an
output by whole and eighth VCO cycles, so its grid is a matter of the
divisor the solver picks -- an output cycle being that many VCO
cycles. The solver will move to a divisor that carries the phase
asked for: a fifth of a cycle needs a divisor that is a multiple of
five, and asking for one at 200 MHz walks the VCO down from 1400 to
1000 to get it. A phase no divisor can carry fails elaboration, like
any other request the block cannot hold.

Phase
-----

`pll_output` takes a `phase`, a fraction of the output's own cycle by
which it is delayed relative to the outputs that state none::

  o1 => pll_output(10_000_000, phase => (num => 1, den => 8))

What a block can hit depends on how it shifts. GW5A's PLLA moves an
output by whole and eighth VCO cycles, so its grid is a matter of the
divisor the solver picks -- an output cycle being that many VCO
cycles. The solver will move to a divisor that carries the phase
asked for: a fifth of a cycle needs a divisor that is a multiple of
five, and asking for one at 200 MHz walks the VCO down from 1400 to
1000 to get it. A phase no divisor can carry fails elaboration, like
any other request the block cannot hold.

Under the hood, `pll_multi` is realized by an elaboration-time solver
working from a description of the vendor PLL block:

* `pll_topology_t` describes what the block can do: legal divisor
  values for every stage, PFD and VCO frequency windows, per-output
  features,

* `mapping_solve()` searches divisor settings satisfying both the
  topology and the config, and returns a `pll_mapping_t` holding the
  realization parameters: divisor of every stage and assignment of
  each requested output to a physical output port.

The solver is a pure deterministic function, exposed as public API
through the `pll_backend` package (`pll_topology_get`,
`pll_solve`). User code needing the achieved rates (for instance when
using `tolerance_ppm`) can call `pll_solve` explicitly and read them
back from the mapping with `mapping_output_hz`; the mapping obtained
this way is the one `pll_multi` implements.

`pll_multi` backends currently include:

* Simulation. Outputs are ideal clocks at the rates of the solved
  mapping, approximations included, so that a tolerance granted in
  the config is observable in simulation just like on hardware.

* Gowin. GW5A parts map on the PLLA block (7 outputs, eighths
  fractional divisor on output 0, phase shift on every output),
  GW1N/GW2A parts map on the rPLL/PLL blocks (single output, no
  phase shift).

* Lattice ECP5, on EHXPLLL with CLKOP reserved for feedback: three
  user outputs on the CLKOS/CLKOS2/CLKOS3 dividers. Phase offsets
  are not supported yet.

* Lattice iCE40, on SB_PLL40 in SIMPLE feedback mode: single output
  on a power-of-two divider. `pll_reference_id` picks the CORE/PAD
  input and `pll_routing_id` the CORE/GLOBAL output.

* Xilinx Series-6 and Series-7, on PLL_BASE, PLLE2_ADV, MMCM_BASE or
  DCM_SP, six outputs but for the DCM's one. The input divider stays
  at 1 and the phase detector window is left open: the per-part limits
  in `nsl_hwconfig` state a VCO window and the two factors, and
  nothing else.

On backends with a `pll_multi` realization, `pll_basic` is a thin
wrapper over it, requesting one exact output: a rate the PLL cannot
reach exactly fails elaboration instead of silently approximating,
unlike the remaining legacy backends which take the closest
reachable rate.
