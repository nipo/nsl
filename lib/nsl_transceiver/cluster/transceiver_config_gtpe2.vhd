library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_transceiver, nsl_math, nsl_hwdep, nsl_data;
use nsl_transceiver.target.all;
use nsl_transceiver.lane.all;
use nsl_math.int_ext.all;
use nsl_data.text.all;

package transceiver_config_gtpe2 is

  -- Types ------------------------------------------------------------
  -- PLL multiplier divider types
  -- Refer to UG482 Table 2-7
  subtype M_t is natural range 1 to 2;
  subtype N2_t is natural range 1 to 5;
  subtype N1_t is natural range 4 to 5;
  subtype D_t is natural range 1 to 8;

  type pll_mult_div_t is
  record
    M  : M_t;
    N2 : N2_t;
    N1 : N1_t;
    D  : D_t;
  end record;

  -- GTPE2 data width type
  -- Internal width is internal to the GTPE2_CHANNEL primitive
  -- Interface is fabric-side width
  type data_width_t is
  record
    internal_width  : natural;
    interface_width : natural;
  end record;

  -- Loopback configuration, two bit vector
  subtype loopback_config_t is std_logic_vector(2 downto 0);

  -- MMCM configuration types
  type params is
  record
    vco_freq    : integer;
    fin_factor  : integer;
    fout_factor : integer;
  end record;

  type pll_variant is (
    S6_PLL,
    S7_MMCM,
    S7_PLL,
    S6_DCM
    );

  type constraints is
  record
    fmin, fmax                    : integer;
    in_factor_max, out_factor_max : integer;
    mode                          : string(1 to 3);
  end record;  

  -- Functions ---------------------------------------------------------
  -- Reference clock vector builder
  -- Assigns clock ID's to correct signals  
  function build_refclk_vec(ids  : integer_vector;
                            clks : std_ulogic_vector)
    return std_ulogic_vector;

  -- PLL multiplier and divider calculator
  function pll_mult_div_assign (line_rate_mhz : natural;
                                pll_vco_mhz   : natural;
                                ref_clk_mhz   : natural)
    return pll_mult_div_t;

  -- Loopback configuration function, see Table 2-27 UG482  
  function loopback_configure (config : nsl_transceiver.lane.loopback_mode_t)
    return std_logic_vector;

  -- Data width calculation, see Table 3-4 UG482  
  function determine_data_width (byte_count : natural)
    return data_width_t;

  -- MMCM configuration for getting TXOUTCLK at the correct frequency
  -- See TX Fabric Clock Output Control UG482
  function constraints_get(mode : pll_variant)
    return constraints;

  function pll_params_calc(fin, fout : integer;
                           mode      : pll_variant)
    return params;

end package;


package body transceiver_config_gtpe2 is

  function build_refclk_vec(ids  : integer_vector;
                            clks : std_ulogic_vector)
    return std_ulogic_vector
  is
    variable v : std_ulogic_vector(0 to 6) := (others => '0');
  begin
    for i in ids'range loop
      v(ids(i)) := clks(i);
    end loop;
    return v;
  end function;

  function pll_mult_div_assign (line_rate_mhz : natural;
                                pll_vco_mhz   : natural;
                                ref_clk_mhz   : natural)
    return pll_mult_div_t
  is
    variable d          : real;
    variable ratio      : real;
    variable pll_config : pll_mult_div_t;
  begin  -- function pll_mult_div_assign
    -- Check valid PLL VCO frequency
    assert (pll_vco_mhz >= 1600 and pll_vco_mhz <= 3300)
      report "transceiver_cluster/gtpe2: Invalid PLL VCO frequency: GTP transceivers accept a range of 1.6GHz to 3.3GHz"
      severity failure;

    -- Calculate D
    d := (real(pll_vco_mhz) * 2.0) / real(line_rate_mhz);
    assert d = 1.0 or d = 2.0 or d = 4.0 or d = 8.0
      report "transceiver_cluster/gtpe2: Invalid PLL VCO to line rate ratio, valid ratios are 1, 2, 4, or 8"
      severity failure;
    pll_config.D := natural(d);

    -- Calculate PLL to Ref ratio and check valid value
    ratio := real(pll_vco_mhz) / real(ref_clk_mhz);
    assert ratio = 2.0 or ratio = 2.5 or ratio = 4.0 or ratio = 5.0 or ratio = 6.0 or ratio = 7.5 or
      ratio = 8.0 or ratio = 10.0 or ratio = 12.0 or ratio = 12.5 or ratio = 15.0 or ratio = 16.0 or
      ratio = 20.0 or ratio = 25.0
      report "transceiver_cluster/gtpe2: Invalid PLL VCO to reference clock ratio, valid ratios are 2, 2.5, 4, 5, 6, 7.5, 8, 10, 12, 12.5, 15, 16, 20, or 25"
      severity failure;

    -- Assign M, N2, and N1
    if ratio = 2.0 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 2.5 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 4.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 5.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 6.0 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 7.5 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 8.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 4;

    elsif ratio = 10.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 5;

    elsif ratio = 12.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 12.5 then
      pll_config.M  := 2;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    elsif ratio = 15.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 16.0 then
      pll_config.M  := 1;
      pll_config.N2 := 4;
      pll_config.N1 := 4;

    elsif ratio = 20.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 4;

    elsif ratio = 25.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    end if;

    return pll_config;
  end function;

  function loopback_configure (config : nsl_transceiver.lane.loopback_mode_t)
    return std_logic_vector
  is
    variable return_val : std_logic_vector(2 downto 0) := (others => '0');
  begin
    case config is
      when nsl_transceiver.lane.LOOPBACK_NONE         => return_val := "000";
      when nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA => return_val := "010";
      when nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS => return_val := "001";
      when nsl_transceiver.lane.LOOPBACK_FAR_END_PMA  => return_val := "100";
      when nsl_transceiver.lane.LOOPBACK_FAR_END_PCS  => return_val := "110";
    end case;
    return return_val;
  end function;

  function determine_data_width (byte_count : natural)
    return data_width_t
  is
    variable return_val : data_width_t;
  begin
    if byte_count <= 2 then
      return_val.internal_width  := 20;
      return_val.interface_width := 16;
    elsif byte_count >= 3 then
      return_val.internal_width  := 40;
      return_val.interface_width := 32;
    end if;
    return return_val;
  end function;

  function constraints_get(mode : pll_variant)
    return constraints
  is
    variable ret : nsl_hwdep.xc7_config.pll_constraints;
  begin
    if mode = S7_MMCM then
      ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.MMCM);
    elsif mode = S7_PLL then
      ret := nsl_hwdep.xc7_config.pll_constraints_get(nsl_hwdep.xc7_config.PLL);
    else
      report "Unsupported mode" severity failure;
    end if;

    return constraints'(
      fmin           => ret.fmin,
      fmax           => ret.fmax,
      in_factor_max  => ret.in_factor_max,
      out_factor_max => ret.out_factor_max,
      mode           => ret.mode
      );
  end function;

  function pll_params_calc(fin, fout : integer;
                           mode      : pll_variant)
    return params
  is
    constant bounds             : constraints := constraints_get(mode);
    variable freq_lcm, vco_mult : integer;
    variable ret                : params;
  begin
    freq_lcm := nsl_math.arith.lcm(fin, fout);

    vco_mult := integer(trunc(realmin(
      real(bounds.fmax) / real(freq_lcm),
      real(bounds.in_factor_max) * real(fin) / real(freq_lcm)
      )));
    if vco_mult = 0 then
      vco_mult := 1;
    end if;

    ret.vco_freq    := freq_lcm * vco_mult;
    ret.fin_factor  := ret.vco_freq / fin;
    ret.fout_factor := ret.vco_freq / fout;

    report "Synthesizing " & bounds.mode & ", "
      & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
      & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
      severity note;
    report "Freq lcm=" & to_string(real(freq_lcm) / 1.0e6) & "MHz, "
      & "vco_freq=" & to_string(real(ret.vco_freq) / 1.0e6) & "MHz "
      & "(min=" & to_string(real(bounds.fmin) / 1.0e6) & "MHz, "
      & "max=" & to_string(real(bounds.fmax) / 1.0e6) & "MHz), "
      & "= fin * " & to_string(ret.fin_factor) & ", "
      & "= fout * " & to_string(ret.fout_factor)
      severity note;

    assert bounds.fmin <= ret.vco_freq and ret.vco_freq <= bounds.fmax
                          report "Needed VCO frequency is out of range"
                          severity failure;

    assert ret.fout_factor <= bounds.out_factor_max
                              report "Clock output frequency is out of range"
                              severity failure;

    assert ret.fin_factor <= bounds.in_factor_max
                             report "Clock input frequency is out of range"
                             severity failure;

    return ret;
  end function;

end package body;
