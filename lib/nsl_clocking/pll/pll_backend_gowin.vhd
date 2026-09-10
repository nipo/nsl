library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig;
use nsl_hwconfig.gowin_config.all;
use work.pll.all;

package body pll_backend is

  -- The block a Gowin part carries is a property of the part, stated
  -- by nsl_hwconfig.gowin_config, not something a design picks:
  -- naming one is accepted only when it is the one the part has.
  -- Reference pins and clock networks are not modeled.
  function pll_reference_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT"
      report "Gowin PLL has no reference input named " & name
      severity failure;
    return 0;
  end function;

  function pll_implementation_id(name: string) return natural
  is
  begin
    assert name = "DEFAULT" or name = "RPLL" or name = "PLL" or name = "PLLA"
      report "Gowin PLL has no implementation named " & name
        & ", expected RPLL, PLL or PLLA"
      severity failure;
    assert name = "DEFAULT"
      or (name = "RPLL" and pll_type = "rpll")
      or (name = "PLL" and pll_type = "pll")
      or (name = "PLLA" and pll_type = "plla")
      report "This part carries a " & pll_type & " block, not a " & name
      severity failure;
    return 0;
  end function;

  -- An output either drives the global clock network through a
  -- buffer, or leaves the block as it comes.  The network carries
  -- far less than a VCO-adjacent rate, so the reference of a second
  -- PLL -- which a cascade takes straight from the first one, well
  -- above what fabric clocks ever run at -- wants NONE.
  constant routing_global_c : natural := 0;
  constant routing_none_c : natural := 1;

  function pll_routing_id(name: string) return natural
  is
  begin
    if name = "DEFAULT" or name = "GLOBAL" then
      return routing_global_c;
    elsif name = "NONE" then
      return routing_none_c;
    end if;
    assert false
      report "Gowin PLL has no output routing named " & name
        & ", expected GLOBAL or NONE"
      severity failure;
    return 0;
  end function;

  -- Fold a plain value list into range/step runs.
  function ranges_from_list(l: ivec) return pll_divisor_constraint_t
  is
    variable ret: pll_divisor_constraint_t;
    variable n: natural := 0;
    variable start, prev, step: integer := 0;
    variable pending: boolean := false;
  begin
    ret.frac_l2_den := 0;
    ret.ranges := (others => pll_range_none_c);

    for i in l'range loop
      if not pending then
        start := l(i);
        prev := start;
        step := 0;
        pending := true;
      elsif step = 0 then
        step := l(i) - start;
        prev := l(i);
      elsif l(i) - prev = step then
        prev := l(i);
      else
        assert n < pll_range_max_c
          report "Divisor list needs too many ranges"
          severity failure;
        if step = 0 then
          ret.ranges(n) := pll_range(start, prev);
        else
          ret.ranges(n) := pll_range(start, prev, step);
        end if;
        n := n + 1;
        start := l(i);
        prev := start;
        step := 0;
      end if;
    end loop;

    if pending then
      assert n < pll_range_max_c
        report "Divisor list needs too many ranges"
        severity failure;
      if step = 0 then
        ret.ranges(n) := pll_range(start, prev);
      else
        ret.ranges(n) := pll_range(start, prev, step);
      end if;
      n := n + 1;
    end if;

    ret.range_count := n;
    return ret;
  end function;

  function gowin_topology return pll_topology_t
  is
    constant odiv_c: pll_divisor_constraint_t := ranges_from_list(pll_odiv_possibilities);
    variable ret: pll_topology_t;
  begin
    ret.refdiv := pll_divisor(pll_range(1, 64));
    ret.postdiv := pll_divisor_unity_c;
    ret.pfd_khz_min := integer(pll_pfd_fmin / 1.0e3);
    ret.pfd_khz_max := integer(pll_pfd_fmax / 1.0e3);
    ret.vco_khz_min := integer(pll_vco_fmin / 1.0e3);
    ret.vco_khz_max := integer(pll_vco_fmax / 1.0e3);
    ret.output := (others => (divisor => pll_divisor_unity_c,
                              phase_den => 0));

    if pll_type = "plla" then
      -- Feedback is realized on MDIV, ODIV0 has an eighths
      -- fractional part.  Phase adjustment steps depend on the
      -- output divisor and are not modeled.
      ret.fbdiv := pll_divisor(pll_range(2, 128));
      ret.output_count := 7;
      for i in 0 to 6 loop
        ret.output(i) := (divisor => odiv_c, phase_den => 0);
      end loop;
      ret.output(0).divisor.frac_l2_den := 3;
    else
      ret.fbdiv := pll_divisor(pll_range(1, 64));
      ret.output_count := 1;
      ret.output(0) := (divisor => odiv_c, phase_den => 0);
    end if;

    return ret;
  end function;

  function pll_topology_get(implementation: natural := 0)
    return pll_topology_t
  is
  begin
    assert implementation = 0
      report "Gowin PLL implementation is a property of the part"
      severity failure;
    return gowin_topology;
  end function;

  function pll_solve(config: pll_config_t) return pll_mapping_t
  is
  begin
    return mapping_solve(pll_topology_get(config.implementation), config);
  end function;

end package body pll_backend;
