library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.text.all;

library machxo2;

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

architecture mxo2 of pll_basic is

  type machxo2_pll_params is
  record
    clki_div, clkfb_div, clkop_div : integer;
  end record;

  type machxo2_pll_constraints is
  record
    fmin, fmax : integer;
    in_factor_max, out_factor_max : integer;
  end record;

  function machxo2_vco_freq(fin : real;
                            params : machxo2_pll_params)
    return real
  is
    variable n, m, v, fvco : real;
  begin
    n := real(params.clkfb_div + 1);
    m := real(params.clki_div + 1);
    v := real(params.clkop_div + 1);

    return fin * n * v / m;
  end function;

  function machxo2_out_freq(fin : real;
                            params : machxo2_pll_params;
                            constraints : machxo2_pll_constraints)
    return real
  is
    variable fvco : real;
  begin
    fvco := machxo2_vco_freq(fin, params);

    if fvco > constraints.fmax or fvco < constraints.fmin then
      return 0.0;
    end if;

    return fvco / real(params.clkop_div + 1);
  end function;

  function machxo2_pll_params_generate(fin, fout : integer;
                                       constraints : machxo2_pll_constraints)
    return machxo2_pll_params
  is
    variable freq_lcm, mult : integer;
    variable vco_freq : integer;
    variable ret : machxo2_pll_params;
  begin
    freq_lcm := nsl_math.arith.lcm(fin, fout);
    mult := (constraints.fmin + constraints.fmax) / 2 / freq_lcm;
    if mult = 0 or mult * freq_lcm < constraints.fmin then
      mult := mult + 1;
    end if;

    vco_freq := freq_lcm * mult;
    ret.clkfb_div := vco_freq / fin;
    ret.clkop_div := vco_freq / fout;
    ret.clki_div := 1;

    assert false
      report "Synthesizing MXO2 PLL, " 
      & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
      & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
      severity note;

    assert false
      report "Freq lcm=" & to_string(real(freq_lcm) / 1.0e6) & "MHz, "
      & "vco_freq=" & to_string(real(vco_freq) / 1.0e6) & "MHz "
      & "(min=" & to_string(real(constraints.fmin) / 1.0e6) & "MHz, "
      & "max=" & to_string(real(constraints.fmax) / 1.0e6) & "MHz), "
      & "= fin * " & to_string(ret.clkfb_div) & ", "
      & "= fout * " & to_string(ret.clkop_div)
      severity note;

    assert constraints.fmin <= vco_freq and vco_freq <= constraints.fmax
      report "Needed VCO frequency is out of range"
      severity failure;

    assert ret.clkop_div <= constraints.out_factor_max
      report "Clock output frequency is out of range"
      severity failure;

    assert ret.clkfb_div <= constraints.in_factor_max
      report "Clock input frequency is out of range"
      severity failure;

    return ret;
  end function;
  
  -- Now the settings
  
  constant pll_constraints : machxo2_pll_constraints := (200000000, 800000000,
                                                         128, 128);
  constant params : machxo2_pll_params := machxo2_pll_params_generate(input_hz_c,
                                                                      output_hz_c,
                                                                      pll_constraints);

  constant fin_str_c : string := to_string(real(input_hz_c) / 1.0e6);
  constant fout_str_c : string := to_string(real(output_hz_c) / 1.0e6);
  signal reset: std_ulogic;

  attribute FREQUENCY_PIN_CLKI: string;
  attribute FREQUENCY_PIN_CLKOP: string;

  attribute FREQUENCY_PIN_CLKI of inst:label is fin_str_c;
  attribute FREQUENCY_PIN_CLKOP of inst:label is fout_str_c;
  
begin

  reset <= not reset_n_i;
  
  inst: machxo2.components.ehxpllj
    generic map(
      -- Actually, only in simulation model
      -- fin => fin_str_c,
      clki_div => params.clki_div,
      clkop_div => params.clkop_div,
      clkfb_div => params.clkfb_div,
      CLKOP_CPHASE     => params.clkop_div-1,
      CLKOP_FPHASE     => 0,

      CLKOS2_DIV       => 1,
      CLKOS3_DIV       => 1,
      CLKOP_ENABLE     => "ENABLED",
      CLKOS_ENABLE     => "DISABLED",
      CLKOS2_ENABLE    => "DISABLED",
      CLKOS3_ENABLE    => "DISABLED",
      CLKOS_CPHASE     => 0,
      CLKOS2_CPHASE    => 0,
      CLKOS3_CPHASE    => 0,
      CLKOS_FPHASE     => 0,
      CLKOS2_FPHASE    => 0,
      CLKOS3_FPHASE    => 0,
      FEEDBK_PATH      => "CLKOP",
      FRACN_ENABLE     => "DISABLED",
      FRACN_DIV        => 0,
      PLL_USE_WB       => "DISABLED",
      CLKOP_TRIM_POL   => "RISING",
      CLKOP_TRIM_DELAY => 0,
      CLKOS_TRIM_POL   => "RISING",
      CLKOS_TRIM_DELAY => 0,
      VCO_BYPASS_A0    => "DISABLED",
      VCO_BYPASS_B0    => "DISABLED",
      VCO_BYPASS_C0    => "DISABLED",
      VCO_BYPASS_D0    => "DISABLED",
      PREDIVIDER_MUXA1 => 0,
      PREDIVIDER_MUXB1 => 0,
      PREDIVIDER_MUXC1 => 0,
      PREDIVIDER_MUXD1 => 0,
      OUTDIVIDER_MUXA2 => "DIVA",
      OUTDIVIDER_MUXB2 => "DIVB",
      OUTDIVIDER_MUXC2 => "DIVC",
      OUTDIVIDER_MUXD2 => "DIVD",
      PLL_LOCK_MODE    => 0,
      DPHASE_SOURCE    => "DISABLED",
      STDBY_ENABLE     => "DISABLED",
      PLLRST_ENA       => "DISABLED",
      MRST_ENA         => "DISABLED",
      DCRST_ENA        => "DISABLED",
      DDRST_ENA        => "DISABLED",
      INTFB_WAKE       => "DISABLED"
      )
    port map(
      clki => clock_i,
      clkfb => '0',
      phasesel1 => '0',
      phasesel0 => '0',
      phasedir => '0',
      phasestep => '0',
      loadreg => '0',
      stdby => '0',
      pllwakesync => '0',
      rst => reset,
      resetm => '0',
      resetc => '0',
      resetd => '0',
      enclkop => '1',
      enclkos => '0',
      enclkos2 => '0',
      enclkos3 => '0',

      pllclk   => '0',
      pllrst   => '0',
      pllstb   => '0',
      pllwe    => '0',
      plladdr4 => '0',
      plladdr3 => '0',
      plladdr2 => '0',
      plladdr1 => '0',
      plladdr0 => '0',
      plldati7 => '0',
      plldati6 => '0',
      plldati5 => '0',
      plldati4 => '0',
      plldati3 => '0',
      plldati2 => '0',
      plldati1 => '0',
      plldati0 => '0',

      clkop => clock_o,
      lock => locked_o
      );
  
end architecture mxo2;
