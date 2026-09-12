library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_synthesis;
use nsl_data.text.all;

-- PLL abstraction.
--
-- Vendor clocking resources usually offer PLLs but
-- they are quite cumbersome to use most of the time because:
--
-- - feedback path is vendor specific and depends on the chip lineup,
--
-- - VCO locking range is chip-specific,
--
-- - There are various competing blocks with different interface for
--   the same service,
--
-- - There are some arbitrary offsets and encodings in dividors that
--   are not obvious from the port and generic names.
--
-- This package gives two entry points:
--
-- - pll_basic, for the minimal case: one input clock of fixed
--   frequency, one output clock of fixed frequency,
--
-- - pll_multi, for one input clock and multiple output clocks, with
--   optional per-output rate tolerance, fractional division and
--   phase offset.
--
-- In both cases, VCO parameters and PLL implementation are taken
-- care of automatically.
--
-- pll_multi rests on an elaboration-time solver split in a
-- backend-agnostic and a backend-specific part:
--
-- - pll_topology_t describes what a vendor PLL block can do: legal
--   divisor values for every stage, PFD and VCO frequency windows,
--   per-output features.  Backends expose a factory returning it,
--
-- - pll_config_t describes what the user wants: input rate, output
--   rates and per-output allowances,
--
-- - mapping_solve() searches divisor settings satisfying both and
--   returns a pll_mapping_t, the realization parameters.  Backends
--   provide an architecture of pll_multi that instantiates vendor
--   primitives from the mapping.
--
-- Requested output rates are exact by default (tolerance_ppm = 0):
-- elaboration fails when no exact realization exists.  When user
-- gives some slack, achieved rates can be retrieved from user code
-- by calling the solver explicitly: it is a pure deterministic
-- function, mapping returned to user code is the one pll_multi
-- implements.
--
-- Modeled PLL structure, in signal flow order:
--
--   input -> refdiv -> PFD -> VCO -> postdiv -> per-output divisor
--                       ^
--   feedback: VCO -> fbdiv
--
-- Blocks without a VCO post divisor use a topology where postdiv
-- only allows value 1.
--
-- Some blocks offer choices no divisor expresses: which pin type the
-- reference comes from, which of several competing blocks to use,
-- which clock network an output is routed to.  Those are named by
-- backend functions turning a string into an opaque integer:
-- pll_reference_id, pll_implementation_id and pll_routing_id, all in
-- the pll_backend package.  The integer travels in pll_config_t, so
-- the generic types carry backend-specific choices without knowing
-- anything about them.  Zero is always the backend's default, so a
-- config that names nothing is portable; a name the backend does not
-- define fails elaboration.
package pll is

  -- Maximum output count of any supported PLL block.
  constant pll_output_max_c : natural := 8;
  -- Maximum range list length in a divisor constraint.
  constant pll_range_max_c : natural := 8;

  -- Rational value.  Used for divisor values (den is a power of two
  -- for fractional divisors, 1 for integer ones) and phase offsets
  -- (fraction of a cycle).
  type pll_ratio_t is
  record
    num: natural;
    den: positive;
  end record;

  constant pll_ratio_zero_c : pll_ratio_t := (num => 0, den => 1);
  constant pll_ratio_one_c : pll_ratio_t := (num => 1, den => 1);

  -- Contiguous set of legal integer values: min, min+step, ... up to
  -- max included.
  type pll_range_t is
  record
    min: natural;
    max: natural;
    step: positive;
  end record;

  -- Empty range (matches no value).
  constant pll_range_none_c : pll_range_t := (min => 1, max => 0, step => 1);

  type pll_range_vector is array (0 to pll_range_max_c-1) of pll_range_t;

  -- Legal values for one divisor stage.  Integer part must fall in
  -- one of the ranges.  frac_l2_den is the log2 of the fractional
  -- part denominator, 0 meaning integer-only.
  --
  -- e.g. "even from 2 to 128, or 3" is expressed as
  -- (2, 128, 2) + (3, 3, 1).
  type pll_divisor_constraint_t is
  record
    range_count: natural range 0 to pll_range_max_c;
    ranges: pll_range_vector;
    frac_l2_den: natural;
  end record;

  -- Divisor stage that only allows not dividing.
  constant pll_divisor_unity_c : pll_divisor_constraint_t := (
    range_count => 1,
    ranges => (0 => (min => 1, max => 1, step => 1),
               others => pll_range_none_c),
    frac_l2_den => 0);

  -- Per-output features of a PLL block.
  --
  -- Phase adjustment comes in two shapes.  phase_den is the count of
  -- selectable positions per output cycle, for a block whose step is
  -- a fraction of what it outputs.  phase_vco_den is the count of
  -- positions per VCO cycle, for a block that shifts the output by
  -- whole and fractional VCO cycles: an output cycle being `divisor`
  -- VCO cycles, its grid is that much finer than the output period,
  -- and depends on the divisor the solver picks.  Either is 0 when
  -- the block does not offer it, and both are 0 on an output with no
  -- phase adjustment at all.
  type pll_output_topology_t is
  record
    divisor: pll_divisor_constraint_t;
    phase_den: natural;
    phase_vco_den: natural;
  end record;

  type pll_output_topology_vector is array (0 to pll_output_max_c-1)
    of pll_output_topology_t;

  -- Description of a vendor PLL block.  Backends expose a factory
  -- returning this record.
  --
  -- Frequency windows are in kHz: VCO rates above 2.1 GHz exist and
  -- do not fit a 32-bit natural in Hz.
  type pll_topology_t is
  record
    refdiv: pll_divisor_constraint_t;
    fbdiv: pll_divisor_constraint_t;
    postdiv: pll_divisor_constraint_t;
    pfd_khz_min: natural;
    pfd_khz_max: natural;
    vco_khz_min: natural;
    vco_khz_max: natural;
    output_count: natural range 0 to pll_output_max_c;
    output: pll_output_topology_vector;
  end record;

  -- One requested output clock.
  --
  -- hz = 0 marks an unused entry.
  --
  -- tolerance_ppm = 0 requires the achieved rate to match exactly
  -- (checked in integer arithmetic).
  --
  -- allow_fractional permits mapping on a fractional divisor, which
  -- trades exact average rate for cycle-to-cycle jitter and loses
  -- phase relation to sibling outputs.
  --
  -- phase delays the output by that fraction of its own cycle,
  -- relative to the undelayed outputs; it is a delay, not an advance,
  -- as measured on a GW5A.  Outputs with a non-zero phase cannot use
  -- fractional division.
  --
  -- routing names the clock network this output drives, from
  -- pll_routing_id.  0 is the backend's default.
  type pll_output_config_t is
  record
    hz: natural;
    tolerance_ppm: natural;
    allow_fractional: boolean;
    phase: pll_ratio_t;
    routing: natural;
  end record;

  constant pll_output_none_c : pll_output_config_t := (
    hz => 0,
    tolerance_ppm => 0,
    allow_fractional => false,
    phase => pll_ratio_zero_c,
    routing => 0);

  type pll_output_config_vector is array (0 to pll_output_max_c-1)
    of pll_output_config_t;

  -- Full user request.
  --
  -- reference_input names the pin type the input clock comes from,
  -- from pll_reference_id.  implementation names which block to use
  -- when the target has several, from pll_implementation_id.  Both
  -- are 0 for the backend's default, and implementation reaches the
  -- topology factory: competing blocks have their own divisors and
  -- frequency windows.
  type pll_config_t is
  record
    input_hz: natural;
    reference_input: natural;
    implementation: natural;
    output_count: natural range 0 to pll_output_max_c;
    output: pll_output_config_vector;
  end record;

  -- Realization parameters for one output.  port_index is the
  -- physical output port of the block that carries this logical
  -- output, letting the solver assign feature-rich ports where
  -- needed.
  type pll_output_mapping_t is
  record
    enabled: boolean;
    port_index: natural range 0 to pll_output_max_c-1;
    divisor: pll_ratio_t;
    hz: natural;
    exact: boolean;
    phase: pll_ratio_t;
  end record;

  type pll_output_mapping_vector is array (0 to pll_output_max_c-1)
    of pll_output_mapping_t;

  -- Realization parameters for the whole block.  valid is false when
  -- the solver found no mapping; pll_multi fails elaboration on it,
  -- user code probing feasibility can test it instead.
  type pll_mapping_t is
  record
    valid: boolean;
    input_hz: natural;
    refdiv: positive;
    fbdiv: pll_ratio_t;
    postdiv: positive;
    pfd_khz: natural;
    vco_khz: natural;
    output_count: natural range 0 to pll_output_max_c;
    output: pll_output_mapping_vector;
  end record;

  -- Config constructors

  function pll_output(hz: natural;
                      tolerance_ppm: natural := 0;
                      allow_fractional: boolean := false;
                      phase: pll_ratio_t := pll_ratio_zero_c;
                      routing: natural := 0)
    return pll_output_config_t;

  function pll_config(input_hz: natural;
                      o0: pll_output_config_t;
                      o1: pll_output_config_t := pll_output_none_c;
                      o2: pll_output_config_t := pll_output_none_c;
                      o3: pll_output_config_t := pll_output_none_c;
                      o4: pll_output_config_t := pll_output_none_c;
                      o5: pll_output_config_t := pll_output_none_c;
                      o6: pll_output_config_t := pll_output_none_c;
                      o7: pll_output_config_t := pll_output_none_c;
                      reference_input: natural := 0;
                      implementation: natural := 0)
    return pll_config_t;

  -- Topology constructors, for backend factories

  function pll_range(min, max: natural;
                     step: positive := 1) return pll_range_t;

  function pll_divisor(r0: pll_range_t;
                       r1: pll_range_t := pll_range_none_c;
                       r2: pll_range_t := pll_range_none_c;
                       r3: pll_range_t := pll_range_none_c;
                       r4: pll_range_t := pll_range_none_c;
                       r5: pll_range_t := pll_range_none_c;
                       r6: pll_range_t := pll_range_none_c;
                       r7: pll_range_t := pll_range_none_c;
                       frac_l2_den: natural := 0)
    return pll_divisor_constraint_t;

  -- Solver

  -- Whether value integer part falls in one of the constraint ranges
  -- and its fractional part fits the constraint denominator.
  function is_allowed(constraint: pll_divisor_constraint_t;
                      value: pll_ratio_t) return boolean;

  -- Backend-agnostic solver.  Deterministic pure function: called
  -- twice on the same arguments, it returns the same mapping.
  -- Returns a mapping with valid = false when config cannot be
  -- satisfied by topology.
  function mapping_solve(topology: pll_topology_t;
                         config: pll_config_t) return pll_mapping_t;

  -- Returns mapping unchanged, failing elaboration when it holds no
  -- realization.  A plain assertion is not enough: some synthesis
  -- front ends carry on past a failed one and build whatever the
  -- unset parameters give, so this goes through
  -- nsl_synthesis.assertion, which fails the elaboration itself.
  function mapping_checked(mapping: pll_mapping_t;
                           config: pll_config_t) return pll_mapping_t;

  -- Exact achieved rate of one output, in Hz.  Unlike the rounded hz
  -- field of the output mapping, this is suitable for computing
  -- periods.
  function mapping_output_hz(mapping: pll_mapping_t;
                             index: natural) return real;

  -- Log helpers
  function to_string(value: pll_ratio_t) return string;
  function to_string(config: pll_config_t) return string;
  function to_string(mapping: pll_mapping_t) return string;

  -- Single-output PLL, for the minimal case.  Block choices beyond
  -- the rates (reference pin type, competing blocks, output routing)
  -- are not reachable here: use pll_multi with a pll_config_t.
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

  -- Multi-output PLL.  Solves and realizes config_c on the target
  -- PLL block.  Fails elaboration when config cannot be satisfied.
  component pll_multi
    generic(
      config_c : pll_config_t
      );
    port(
      clock_i : in std_ulogic;
      clock_o : out std_ulogic_vector(0 to config_c.output_count-1);

      reset_n_i : in std_ulogic;
      locked_o : out std_ulogic
      );
  end component;

end package pll;

package body pll is

  function gcd(a, b: natural) return natural
  is
    variable x: natural := a;
    variable y: natural := b;
    variable t: natural;
  begin
    while y /= 0 loop
      t := x mod y;
      x := y;
      y := t;
    end loop;
    return x;
  end function;

  -- Multiply with cross-reduction, keeping intermediate products
  -- small.
  function ratio_mul(a, b: pll_ratio_t) return pll_ratio_t
  is
    variable g1, g2: positive;
  begin
    g1 := gcd(a.num, b.den);
    g2 := gcd(b.num, a.den);
    return (num => (a.num / g1) * (b.num / g2),
            den => (a.den / g2) * (b.den / g1));
  end function;

  -- Whether in_hz * r is exactly out_hz, in integer arithmetic.
  function rate_matches(in_hz, out_hz: natural;
                        r: pll_ratio_t) return boolean
  is
    variable g: positive;
    variable n, d, ih: natural;
  begin
    g := gcd(r.num, r.den);
    n := r.num / g;
    d := r.den / g;
    g := gcd(in_hz, d);
    ih := in_hz / g;
    d := d / g;
    -- After reduction, d is coprime to both n and ih: achieved rate
    -- is an integer only for d = 1.
    if d /= 1 then
      return false;
    end if;
    if ih = 0 then
      return out_hz = 0;
    end if;
    return (out_hz mod ih) = 0 and (out_hz / ih) = n;
  end function;

  function is_allowed(constraint: pll_divisor_constraint_t;
                      value: pll_ratio_t) return boolean
  is
    variable g: positive;
    variable d, l, ipart: natural;
  begin
    if value.num = 0 then
      return false;
    end if;

    -- Fractional part must sit on the 1 / 2**frac_l2_den grid:
    -- reduced denominator must be a power of two not larger than it.
    g := gcd(value.num, value.den);
    d := value.den / g;
    l := 0;
    while d mod 2 = 0 loop
      d := d / 2;
      l := l + 1;
    end loop;
    if d /= 1 or l > constraint.frac_l2_den then
      return false;
    end if;

    ipart := value.num / value.den;
    for i in 0 to pll_range_max_c - 1 loop
      if i < constraint.range_count then
        if ipart >= constraint.ranges(i).min
          and ipart <= constraint.ranges(i).max
          and (ipart - constraint.ranges(i).min)
              mod constraint.ranges(i).step = 0 then
          return true;
        end if;
      end if;
    end loop;
    return false;
  end function;

  function constraint_int_max(constraint: pll_divisor_constraint_t)
    return natural
  is
    variable ret: natural := 0;
  begin
    for i in 0 to pll_range_max_c - 1 loop
      if i < constraint.range_count then
        if constraint.ranges(i).max > ret then
          ret := constraint.ranges(i).max;
        end if;
      end if;
    end loop;
    return ret;
  end function;

  -- Config constructors

  function pll_range(min, max: natural;
                     step: positive := 1) return pll_range_t
  is
  begin
    return (min => min, max => max, step => step);
  end function;

  function pll_divisor(r0: pll_range_t;
                       r1: pll_range_t := pll_range_none_c;
                       r2: pll_range_t := pll_range_none_c;
                       r3: pll_range_t := pll_range_none_c;
                       r4: pll_range_t := pll_range_none_c;
                       r5: pll_range_t := pll_range_none_c;
                       r6: pll_range_t := pll_range_none_c;
                       r7: pll_range_t := pll_range_none_c;
                       frac_l2_den: natural := 0)
    return pll_divisor_constraint_t
  is
    constant all_c: pll_range_vector := (r0, r1, r2, r3, r4, r5, r6, r7);
    variable ret: pll_divisor_constraint_t;
    variable n: natural := 0;
  begin
    ret.ranges := (others => pll_range_none_c);
    ret.frac_l2_den := frac_l2_den;
    for i in all_c'range loop
      if all_c(i).max >= all_c(i).min then
        ret.ranges(n) := all_c(i);
        n := n + 1;
      end if;
    end loop;
    ret.range_count := n;
    return ret;
  end function;

  function pll_output(hz: natural;
                      tolerance_ppm: natural := 0;
                      allow_fractional: boolean := false;
                      phase: pll_ratio_t := pll_ratio_zero_c;
                      routing: natural := 0)
    return pll_output_config_t
  is
  begin
    return (hz => hz,
            tolerance_ppm => tolerance_ppm,
            allow_fractional => allow_fractional,
            phase => phase,
            routing => routing);
  end function;

  function pll_config(input_hz: natural;
                      o0: pll_output_config_t;
                      o1: pll_output_config_t := pll_output_none_c;
                      o2: pll_output_config_t := pll_output_none_c;
                      o3: pll_output_config_t := pll_output_none_c;
                      o4: pll_output_config_t := pll_output_none_c;
                      o5: pll_output_config_t := pll_output_none_c;
                      o6: pll_output_config_t := pll_output_none_c;
                      o7: pll_output_config_t := pll_output_none_c;
                      reference_input: natural := 0;
                      implementation: natural := 0)
    return pll_config_t
  is
    constant all_c: pll_output_config_vector := (o0, o1, o2, o3,
                                                 o4, o5, o6, o7);
    variable ret: pll_config_t;
    variable n: natural := 0;
    variable ended: boolean := false;
  begin
    ret.input_hz := input_hz;
    ret.reference_input := reference_input;
    ret.implementation := implementation;
    ret.output := all_c;
    for i in all_c'range loop
      if all_c(i).hz = 0 then
        ended := true;
      else
        assert not ended
          report "PLL output list must be contiguous"
          severity failure;
        n := i + 1;
      end if;
    end loop;
    ret.output_count := n;
    return ret;
  end function;

  -- Log helpers

  function to_string(value: pll_ratio_t) return string
  is
  begin
    if value.num mod value.den = 0 then
      return to_string(value.num / value.den);
    end if;
    return to_string(value.num / value.den)
      & "+" & to_string(value.num mod value.den)
      & "/" & to_string(value.den);
  end function;

  function config_outputs_to_string(config: pll_config_t;
                                    index: natural) return string
  is
  begin
    if index >= config.output_count then
      return "";
    end if;
    return " out" & to_string(index)
      & "=" & to_string(config.output(index).hz) & "Hz"
      & "~" & to_string(config.output(index).tolerance_ppm) & "ppm"
      & config_outputs_to_string(config, index + 1);
  end function;

  function ids_to_string(config: pll_config_t) return string
  is
  begin
    if config.reference_input = 0 and config.implementation = 0 then
      return "";
    end if;
    return " ref=" & to_string(config.reference_input)
      & " impl=" & to_string(config.implementation);
  end function;

  function to_string(config: pll_config_t) return string
  is
  begin
    return "<pll in=" & to_string(config.input_hz) & "Hz"
      & ids_to_string(config)
      & config_outputs_to_string(config, 0)
      & ">";
  end function;

  function phase_to_string(phase: pll_ratio_t) return string
  is
  begin
    if phase.num = 0 then
      return "";
    end if;
    return " phase=" & to_string(phase);
  end function;

  function mapping_outputs_to_string(mapping: pll_mapping_t;
                                     index: natural) return string
  is
  begin
    if index >= mapping.output_count then
      return "";
    end if;
    if not mapping.output(index).exact then
      return " out" & to_string(index)
        & "=" & to_string(mapping.output(index).hz) & "Hz(approx)"
        & "@port" & to_string(mapping.output(index).port_index)
        & " div=" & to_string(mapping.output(index).divisor)
        & phase_to_string(mapping.output(index).phase)
        & mapping_outputs_to_string(mapping, index + 1);
    end if;
    return " out" & to_string(index)
      & "=" & to_string(mapping.output(index).hz) & "Hz"
      & "@port" & to_string(mapping.output(index).port_index)
      & " div=" & to_string(mapping.output(index).divisor)
      & phase_to_string(mapping.output(index).phase)
      & mapping_outputs_to_string(mapping, index + 1);
  end function;

  function to_string(mapping: pll_mapping_t) return string
  is
  begin
    if not mapping.valid then
      return "<mapping invalid>";
    end if;
    return "<mapping refdiv=" & to_string(mapping.refdiv)
      & " fbdiv=" & to_string(mapping.fbdiv)
      & " postdiv=" & to_string(mapping.postdiv)
      & " pfd=" & to_string(mapping.pfd_khz) & "kHz"
      & " vco=" & to_string(mapping.vco_khz) & "kHz"
      & mapping_outputs_to_string(mapping, 0)
      & ">";
  end function;

  -- Solver internals

  type solve_output_t is
  record
    usable: boolean;
    divisor: pll_ratio_t;
    hz: natural;
    exact: boolean;
    err_ppm: real;
  end record;

  constant solve_output_none_c : solve_output_t := (
    usable => false,
    divisor => pll_ratio_one_c,
    hz => 0,
    exact => false,
    err_ppm => 0.0);

  constant output_mapping_none_c : pll_output_mapping_t := (
    enabled => false,
    port_index => 0,
    divisor => pll_ratio_one_c,
    hz => 0,
    exact => false,
    phase => pll_ratio_zero_c);

  type solve_matrix_t is array (0 to pll_output_max_c - 1,
                                0 to pll_output_max_c - 1)
    of solve_output_t;

  type bool_vector_t is array (0 to pll_output_max_c - 1) of boolean;

  type solve_result_t is
  record
    ok: boolean;
    err_ppm: real;
    mapping: pll_mapping_t;
  end record;

  -- Whether a phase offset, stated as a fraction of the output
  -- cycle, lands on a grid this port can hit with this divisor.
  function phase_is_allowed(port_topo: pll_output_topology_t;
                            phase: pll_ratio_t;
                            divisor: pll_ratio_t) return boolean
  is
    variable den: natural;
  begin
    if phase.num = 0 then
      return true;
    end if;

    -- A grid stated per output cycle holds whatever the divisor is
    if port_topo.phase_den /= 0
      and (phase.num * port_topo.phase_den) mod phase.den = 0 then
      return true;
    end if;

    -- A grid stated per VCO cycle needs a whole number of VCO cycles
    -- per output cycle to mean anything
    if port_topo.phase_vco_den /= 0
      and divisor.num mod divisor.den = 0 then
      den := port_topo.phase_vco_den * (divisor.num / divisor.den);
      if (phase.num * den) mod phase.den = 0 then
        return true;
      end if;
    end if;

    return false;
  end function;

  -- Evaluate one output divisor candidate against one requested
  -- output.  dist_ratio is the input-to-distribution-tree rate
  -- ratio, dist_hz_r its rate in Hz.
  function candidate_eval(cfg: pll_output_config_t;
                          in_hz: natural;
                          dist_ratio: pll_ratio_t;
                          dist_hz_r: real;
                          od: pll_ratio_t;
                          port_topo: pll_output_topology_t)
    return solve_output_t
  is
    variable ret: solve_output_t := solve_output_none_c;
    variable achieved_r: real;
  begin
    if not is_allowed(port_topo.divisor, od) then
      return ret;
    end if;

    ret.divisor := od;
    ret.exact := rate_matches(in_hz, cfg.hz,
                              ratio_mul(dist_ratio,
                                        (num => od.den, den => od.num)));
    if ret.exact then
      ret.hz := cfg.hz;
      ret.err_ppm := 0.0;
      ret.usable := true;
    else
      achieved_r := dist_hz_r * real(od.den) / real(od.num);
      ret.err_ppm := abs(achieved_r - real(cfg.hz)) / real(cfg.hz) * 1.0e6;
      ret.usable := cfg.tolerance_ppm /= 0
        and ret.err_ppm <= real(cfg.tolerance_ppm);
      if ret.usable then
        ret.hz := natural(achieved_r);
      end if;
    end if;

    -- Requested phase must sit on the port's phase grid, and a
    -- fractional divisor holds no phase relation at all.
    if cfg.phase.num /= 0
      and not phase_is_allowed(port_topo, cfg.phase, od) then
      ret.usable := false;
    end if;

    return ret;
  end function;

  -- Best divisor for one requested output on one physical port,
  -- given the distribution tree rate.  Candidates are picked
  -- analytically around the ideal divisor instead of enumerating
  -- constraint ranges, keeping elaboration cost low.
  function output_solve(cfg: pll_output_config_t;
                        in_hz: natural;
                        dist_ratio: pll_ratio_t;
                        dist_hz_r: real;
                        port_topo: pll_output_topology_t)
    return solve_output_t
  is
    variable best, cand: solve_output_t := solve_output_none_c;
    variable ideal_r: real;
    variable r: pll_range_t;
    variable count, base, den, num_max: natural;
    variable k, num: integer;
  begin
    if cfg.hz = 0 then
      return best;
    end if;
    ideal_r := dist_hz_r / real(cfg.hz);

    int_ranges: for ri in 0 to pll_range_max_c - 1 loop
      if ri >= port_topo.divisor.range_count then
        next int_ranges;
      end if;
      r := port_topo.divisor.ranges(ri);
      if r.max < r.min then
        next int_ranges;
      end if;
      count := (r.max - r.min) / r.step + 1;
      if ideal_r <= real(r.min) then
        base := 0;
      elsif ideal_r >= real(r.max) then
        base := count - 1;
      else
        base := natural((ideal_r - real(r.min)) / real(r.step));
      end if;
      int_deltas: for delta in -2 to 2 loop
        k := base + delta;
        if k < 0 then
          k := 0;
        end if;
        if k > count - 1 then
          k := count - 1;
        end if;
        cand := candidate_eval(cfg, in_hz, dist_ratio, dist_hz_r,
                               (num => r.min + k * r.step, den => 1),
                               port_topo);
        if cand.usable
          and (not best.usable or cand.err_ppm < best.err_ppm) then
          best := cand;
        end if;
      end loop;
    end loop;

    if cfg.allow_fractional
      and port_topo.divisor.frac_l2_den > 0
      and cfg.phase.num = 0 then
      den := 2 ** port_topo.divisor.frac_l2_den;
      num_max := (constraint_int_max(port_topo.divisor) + 1) * den;
      if ideal_r * real(den) >= real(num_max) then
        base := num_max;
      else
        base := natural(ideal_r * real(den));
      end if;
      frac_deltas: for delta in -2 to 2 loop
        num := base + delta;
        if num < 1 then
          next frac_deltas;
        end if;
        cand := candidate_eval(cfg, in_hz, dist_ratio, dist_hz_r,
                               (num => num, den => den),
                               port_topo);
        if cand.usable
          and (not best.usable or cand.err_ppm < best.err_ppm) then
          best := cand;
        end if;
      end loop;
    end if;

    return best;
  end function;

  -- Solve output-to-port assignment for one (refdiv, fbdiv,
  -- postdiv) candidate.  Most constrained output is placed first, on
  -- its lowest-error free port.
  function candidate_solve(topology: pll_topology_t;
                           config: pll_config_t;
                           refdiv, postdiv: positive;
                           fbdiv: pll_ratio_t;
                           pfd_khz, vco_khz: natural;
                           dist_hz_r: real)
    return solve_result_t
  is
    variable sol: solve_matrix_t := (others => (others => solve_output_none_c));
    variable placed, port_used: bool_vector_t := (others => false);
    variable ret: solve_result_t;
    variable dist_ratio: pll_ratio_t;
    variable feas, best_feas: natural;
    variable sel, selp: integer;
    variable best_err: real;
  begin
    ret.ok := false;
    ret.err_ppm := 0.0;
    ret.mapping := (
      valid => false,
      input_hz => config.input_hz,
      refdiv => refdiv,
      fbdiv => fbdiv,
      postdiv => postdiv,
      pfd_khz => pfd_khz,
      vco_khz => vco_khz,
      output_count => config.output_count,
      output => (others => output_mapping_none_c));

    dist_ratio := ratio_mul(fbdiv, (num => 1, den => refdiv * postdiv));

    for i in 0 to pll_output_max_c - 1 loop
      for p in 0 to pll_output_max_c - 1 loop
        if i < config.output_count and p < topology.output_count then
          sol(i, p) := output_solve(config.output(i), config.input_hz,
                                    dist_ratio, dist_hz_r,
                                    topology.output(p));
        end if;
      end loop;
    end loop;

    rounds: for round in 0 to config.output_count - 1 loop
      -- Most constrained output first
      sel := -1;
      best_feas := pll_output_max_c + 1;
      for i in 0 to config.output_count - 1 loop
        if not placed(i) then
          feas := 0;
          for p in 0 to topology.output_count - 1 loop
            if sol(i, p).usable and not port_used(p) then
              feas := feas + 1;
            end if;
          end loop;
          if feas < best_feas then
            best_feas := feas;
            sel := i;
          end if;
        end if;
      end loop;

      if best_feas = 0 then
        return ret;
      end if;

      -- Lowest error free port, ties on lowest index
      selp := -1;
      best_err := 0.0;
      for p in 0 to topology.output_count - 1 loop
        if sol(sel, p).usable and not port_used(p) then
          if selp = -1 or sol(sel, p).err_ppm < best_err then
            selp := p;
            best_err := sol(sel, p).err_ppm;
          end if;
        end if;
      end loop;

      placed(sel) := true;
      port_used(selp) := true;
      ret.mapping.output(sel) := (
        enabled => true,
        port_index => selp,
        divisor => sol(sel, selp).divisor,
        hz => sol(sel, selp).hz,
        exact => sol(sel, selp).exact,
        phase => config.output(sel).phase);
      ret.err_ppm := ret.err_ppm + best_err;
    end loop;

    ret.ok := true;
    ret.mapping.valid := true;
    return ret;
  end function;

  -- Iteration order encodes the preference among equal-error
  -- mappings: refdiv ascending prefers the highest PFD rate, fbdiv
  -- descending prefers the highest VCO rate.  Range lists are
  -- expected in ascending order.
  function mapping_solve(topology: pll_topology_t;
                         config: pll_config_t) return pll_mapping_t
  is
    variable best: pll_mapping_t;
    variable best_err: real := 0.0;
    variable have_best: boolean := false;
    variable res: solve_result_t;
    variable rr, fr, pr: pll_range_t;
    variable rd, fb, pd: natural;
    variable pfd_r, vco_r, dist_r: real;
  begin
    assert config.input_hz > 0
      report "PLL input rate is not set"
      severity failure;
    assert config.output_count >= 1
      report "PLL config has no output"
      severity failure;
    assert config.output_count <= topology.output_count
      report "More outputs requested than PLL block provides"
      severity failure;
    assert topology.refdiv.frac_l2_den = 0
      and topology.postdiv.frac_l2_den = 0
      report "Fractional reference/post divisors are not supported"
      severity failure;
    assert topology.fbdiv.frac_l2_den = 0
      report "Fractional feedback solving is not implemented"
      severity failure;

    best := (
      valid => false,
      input_hz => config.input_hz,
      refdiv => 1,
      fbdiv => pll_ratio_one_c,
      postdiv => 1,
      pfd_khz => 0,
      vco_khz => 0,
      output_count => config.output_count,
      output => (others => output_mapping_none_c));

    rd_ranges: for rri in 0 to pll_range_max_c - 1 loop
      if rri >= topology.refdiv.range_count then
        next rd_ranges;
      end if;
      rr := topology.refdiv.ranges(rri);
      if rr.max < rr.min then
        next rd_ranges;
      end if;
      rd_values: for rk in 0 to (rr.max - rr.min) / rr.step loop
        rd := rr.min + rk * rr.step;
        if rd = 0 then
          next rd_values;
        end if;
        pfd_r := real(config.input_hz) / real(rd);
        if pfd_r < real(topology.pfd_khz_min) * 1000.0
          or pfd_r > real(topology.pfd_khz_max) * 1000.0 then
          next rd_values;
        end if;

        fb_ranges: for fri in pll_range_max_c - 1 downto 0 loop
          if fri >= topology.fbdiv.range_count then
            next fb_ranges;
          end if;
          fr := topology.fbdiv.ranges(fri);
          if fr.max < fr.min then
            next fb_ranges;
          end if;
          fb_values: for fk in (fr.max - fr.min) / fr.step downto 0 loop
            fb := fr.min + fk * fr.step;
            if fb = 0 then
              next fb_values;
            end if;
            vco_r := pfd_r * real(fb);
            if vco_r < real(topology.vco_khz_min) * 1000.0
              or vco_r > real(topology.vco_khz_max) * 1000.0 then
              next fb_values;
            end if;

            pd_ranges: for pri in 0 to pll_range_max_c - 1 loop
              if pri >= topology.postdiv.range_count then
                next pd_ranges;
              end if;
              pr := topology.postdiv.ranges(pri);
              if pr.max < pr.min then
                next pd_ranges;
              end if;
              pd_values: for pk in 0 to (pr.max - pr.min) / pr.step loop
                pd := pr.min + pk * pr.step;
                if pd = 0 then
                  next pd_values;
                end if;
                dist_r := vco_r / real(pd);

                res := candidate_solve(topology, config,
                                       rd, pd,
                                       (num => fb, den => 1),
                                       natural(pfd_r / 1000.0),
                                       natural(vco_r / 1000.0),
                                       dist_r);
                if res.ok
                  and (not have_best or res.err_ppm < best_err) then
                  best := res.mapping;
                  best_err := res.err_ppm;
                  have_best := true;
                  -- An all-exact mapping can only be tied, and ties
                  -- keep the first found
                  if best_err = 0.0 then
                    exit rd_ranges;
                  end if;
                end if;
              end loop;
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;

    return best;
  end function;

  function mapping_checked(mapping: pll_mapping_t;
                           config: pll_config_t) return pll_mapping_t
  is
  begin
    nsl_synthesis.assertion.synth_assert_proc(
      mapping.valid,
      "Cannot map " & to_string(config) & " on this PLL");
    return mapping;
  end function;

  function mapping_output_hz(mapping: pll_mapping_t;
                             index: natural) return real
  is
  begin
    assert mapping.valid
      report "Rate of an invalid mapping"
      severity failure;
    assert index < mapping.output_count and mapping.output(index).enabled
      report "Rate of an unmapped output"
      severity failure;
    return real(mapping.input_hz)
      * real(mapping.fbdiv.num)
      * real(mapping.output(index).divisor.den)
      / real(mapping.refdiv)
      / real(mapping.fbdiv.den)
      / real(mapping.postdiv)
      / real(mapping.output(index).divisor.num);
  end function;

end package body pll;
