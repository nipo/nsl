library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim, nsl_math, nsl_logic, nsl_data;
use nsl_logic.bool.all;
use nsl_data.text.all;

entity pll_basic is
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
end entity;

architecture s6 of pll_basic is

  type params is
  record
    vco_freq : integer;
    fin_factor : integer;
    fout_factor : integer;
  end record;

  type constraints is
  record
    fmin, fmax : integer;
    in_factor_max, out_factor_max : integer;
    mode : string(1 to 3);
  end record;
  
  function pll_params_calc(fin, fout : integer;
                           constraints : constraints) return params
  is
    variable freq_lcm, mult : integer;
    variable ret : params;
  begin
    freq_lcm := nsl_math.arith.lcm(fin, fout);
    mult := constraints.fmin / freq_lcm;
    if mult = 0 or mult * freq_lcm < constraints.fmin then
      mult := mult + 1;
    end if;

    ret.vco_freq := freq_lcm * mult;
    ret.fin_factor := ret.vco_freq / fin;
    ret.fout_factor := ret.vco_freq / fout;

    assert false
      report "Synthesizing S6 " & constraints.mode & ", " 
      & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
      & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
      severity note;
    assert false
      report "Freq lcm=" & to_string(real(freq_lcm) / 1.0e6) & "MHz, "
      & "vco_freq=" & to_string(real(ret.vco_freq) / 1.0e6) & "MHz "
      & "(min=" & to_string(real(constraints.fmin) / 1.0e6) & "MHz, "
      & "max=" & to_string(real(constraints.fmax) / 1.0e6) & "MHz), "
      & "= fin * " & to_string(ret.fin_factor) & ", "
      & "= fout * " & to_string(ret.fout_factor)
      severity note;

    assert constraints.fmin <= ret.vco_freq and ret.vco_freq <= constraints.fmax
      report "Needed VCO frequency is out of range"
      severity failure;

    assert ret.fout_factor <= constraints.out_factor_max
      report "Clock output frequency is out of range"
      severity failure;

    assert ret.fin_factor <= constraints.in_factor_max
      report "Clock input frequency is out of range"
      severity failure;

    return ret;
  end function;

  constant pll_constraints : constraints := (400000000, 1000000000, 64, 128, "PLL");
  constant dcm_constraints : constraints := (5000000, 375000000, 32, 32, "DCM");

  type pll_variant is (
    S6_PLL,
    S6_DCM
    );

  function variant_get(hw_variant : string)
    return pll_variant
  is
  begin
    if strfind(hw_variant, "type=dcm", ',') then
      return S6_DCM;
    else
      return S6_PLL;
    end if;
  end function;

  constant series67_params := str_param_extract(hw_variant_c, "series67");
  constant variant : pll_variant := variant_get(series67);

  signal s_reset : std_ulogic;
  
begin

  s_reset <= not reset_n_i;

  use_pll: if variant = S6_PLL
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(
      input_hz_c, output_hz_c, pll_constraints);
    signal s_feedback : std_ulogic;
  begin
    
    pll_inst: unisim.vcomponents.pll_base
      generic map (
        clk_feedback         => "CLKFBOUT",
        divclk_divide        => 1,
        clkfbout_mult        => p.fin_factor,
        clkout0_divide       => p.fout_factor,
        clkin_period         => input_period_ns_c,
        ref_jitter           => 0.125
        )
      port map (
        rst                 => s_reset,
        clkin               => clock_i,

        clkout0             => clock_o,
        locked              => locked_o,

        clkfbin             => s_feedback,
        clkfbout            => s_feedback
        );
  end generate;

  use_dcm: if variant = S6_DCM
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(
      input_hz_c, output_hz_c, dcm_constraints);
    signal s_feedback : std_ulogic;
    constant is_d2 : boolean := p.fin_factor = 1;
  begin
    
    dcm_inst: unisim.vcomponents.dcm_sp
      generic map(
        clkin_period => input_period_ns_c,

        -- DCM cannot do less than multiply by 2, so do multiply by 2 when we
        -- actually expect 1 multiplication factor, and devide input by two in
        -- exchange.
        clkfx_multiply => if_else(is_d2, 2, p.fin_factor),
        clkin_divide_by_2 => is_d2,

        clkfx_divide => p.fout_factor
        )
      port map(
        clkin => clock_i,
        rst => s_reset,
        clkfx => clock_o,
        locked => locked_o
        );
  end generate;

end architecture;
