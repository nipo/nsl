library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_logic, nsl_data, nsl_clocking;
use nsl_logic.bool.all;
use nsl_data.text.all;
use nsl_clocking.pll_config_series67.all;

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

  attribute BOX_TYPE : string;

  component PLL_BASE
    generic (
      BANDWIDTH : string := "OPTIMIZED";
      CLKFBOUT_MULT : integer := 1;
      CLKFBOUT_PHASE : real := 0.0;
      CLKIN_PERIOD : real := 0.000;
      CLKOUT0_DIVIDE : integer := 1;
      CLKOUT0_DUTY_CYCLE : real := 0.5;
      CLKOUT0_PHASE : real := 0.0;
      CLKOUT1_DIVIDE : integer := 1;
      CLKOUT1_DUTY_CYCLE : real := 0.5;
      CLKOUT1_PHASE : real := 0.0;
      CLKOUT2_DIVIDE : integer := 1;
      CLKOUT2_DUTY_CYCLE : real := 0.5;
      CLKOUT2_PHASE : real := 0.0;
      CLKOUT3_DIVIDE : integer := 1;
      CLKOUT3_DUTY_CYCLE : real := 0.5;
      CLKOUT3_PHASE : real := 0.0;
      CLKOUT4_DIVIDE : integer := 1;
      CLKOUT4_DUTY_CYCLE : real := 0.5;
      CLKOUT4_PHASE : real := 0.0;
      CLKOUT5_DIVIDE : integer := 1;
      CLKOUT5_DUTY_CYCLE : real := 0.5;
      CLKOUT5_PHASE : real := 0.0;
      CLK_FEEDBACK : string := "CLKFBOUT";
      COMPENSATION : string := "SYSTEM_SYNCHRONOUS";
      DIVCLK_DIVIDE : integer := 1;
      REF_JITTER : real := 0.100;
      RESET_ON_LOSS_OF_LOCK : boolean := FALSE
      );
    port (
      CLKFBOUT : out std_ulogic;
      CLKOUT0 : out std_ulogic;
      CLKOUT1 : out std_ulogic;
      CLKOUT2 : out std_ulogic;
      CLKOUT3 : out std_ulogic;
      CLKOUT4 : out std_ulogic;
      CLKOUT5 : out std_ulogic;
      LOCKED : out std_ulogic;
      CLKFBIN : in std_ulogic;
      CLKIN : in std_ulogic;
      RST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    PLL_BASE : component is "PRIMITIVE";

  component PLLE2_ADV
    generic (
      BANDWIDTH : string := "OPTIMIZED";
      CLKFBOUT_MULT : integer := 5;
      CLKFBOUT_PHASE : real := 0.0;
      CLKIN1_PERIOD : real := 0.0;
      CLKIN2_PERIOD : real := 0.0;
      CLKOUT0_DIVIDE : integer := 1;
      CLKOUT0_DUTY_CYCLE : real := 0.5;
      CLKOUT0_PHASE : real := 0.0;
      CLKOUT1_DIVIDE : integer := 1;
      CLKOUT1_DUTY_CYCLE : real := 0.5;
      CLKOUT1_PHASE : real := 0.0;
      CLKOUT2_DIVIDE : integer := 1;
      CLKOUT2_DUTY_CYCLE : real := 0.5;
      CLKOUT2_PHASE : real := 0.0;
      CLKOUT3_DIVIDE : integer := 1;
      CLKOUT3_DUTY_CYCLE : real := 0.5;
      CLKOUT3_PHASE : real := 0.0;
      CLKOUT4_DIVIDE : integer := 1;
      CLKOUT4_DUTY_CYCLE : real := 0.5;
      CLKOUT4_PHASE : real := 0.0;
      CLKOUT5_DIVIDE : integer := 1;
      CLKOUT5_DUTY_CYCLE : real := 0.5;
      CLKOUT5_PHASE : real := 0.0;
      COMPENSATION : string := "ZHOLD";
      DIVCLK_DIVIDE : integer := 1;
      REF_JITTER1 : real := 0.0;
      REF_JITTER2 : real := 0.0;
      STARTUP_WAIT : string := "FALSE"
      );
    port (
      CLKFBOUT : out std_ulogic := '0';
      CLKOUT0 : out std_ulogic := '0';
      CLKOUT1 : out std_ulogic := '0';
      CLKOUT2 : out std_ulogic := '0';
      CLKOUT3 : out std_ulogic := '0';
      CLKOUT4 : out std_ulogic := '0';
      CLKOUT5 : out std_ulogic := '0';
      DO : out std_logic_vector (15 downto 0);
      DRDY : out std_ulogic := '0';
      LOCKED : out std_ulogic := '0';
      CLKFBIN : in std_ulogic;
      CLKIN1 : in std_ulogic;
      CLKIN2 : in std_ulogic;
      CLKINSEL : in std_ulogic;
      DADDR : in std_logic_vector(6 downto 0);
      DCLK : in std_ulogic;
      DEN : in std_ulogic;
      DI : in std_logic_vector(15 downto 0);
      DWE : in std_ulogic;
      PWRDWN : in std_ulogic;
      RST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    PLLE2_ADV : component is "PRIMITIVE";

  component MMCM_BASE
    generic (
      BANDWIDTH : string := "OPTIMIZED";
      CLKFBOUT_MULT_F : real := 5.000;
      CLKFBOUT_PHASE : real := 0.000;
      CLKIN1_PERIOD : real := 0.000;
      CLKOUT0_DIVIDE_F : real := 1.000;
      CLKOUT0_DUTY_CYCLE : real := 0.500;
      CLKOUT0_PHASE : real := 0.000;
      CLKOUT1_DIVIDE : integer := 1;
      CLKOUT1_DUTY_CYCLE : real := 0.500;
      CLKOUT1_PHASE : real := 0.000;
      CLKOUT2_DIVIDE : integer := 1;
      CLKOUT2_DUTY_CYCLE : real := 0.500;
      CLKOUT2_PHASE : real := 0.000;
      CLKOUT3_DIVIDE : integer := 1;
      CLKOUT3_DUTY_CYCLE : real := 0.500;
      CLKOUT3_PHASE : real := 0.000;
      CLKOUT4_CASCADE : boolean := FALSE;
      CLKOUT4_DIVIDE : integer := 1;
      CLKOUT4_DUTY_CYCLE : real := 0.500;
      CLKOUT4_PHASE : real := 0.000;
      CLKOUT5_DIVIDE : integer := 1;
      CLKOUT5_DUTY_CYCLE : real := 0.500;
      CLKOUT5_PHASE : real := 0.000;
      CLKOUT6_DIVIDE : integer := 1;
      CLKOUT6_DUTY_CYCLE : real := 0.500;
      CLKOUT6_PHASE : real := 0.000;
      CLOCK_HOLD : boolean := FALSE;
      DIVCLK_DIVIDE : integer := 1;
      REF_JITTER1 : real := 0.010;
      STARTUP_WAIT : boolean := FALSE
      );
    port (
      CLKFBOUT : out std_ulogic;
      CLKFBOUTB : out std_ulogic;
      CLKOUT0 : out std_ulogic;
      CLKOUT0B : out std_ulogic;
      CLKOUT1 : out std_ulogic;
      CLKOUT1B : out std_ulogic;
      CLKOUT2 : out std_ulogic;
      CLKOUT2B : out std_ulogic;
      CLKOUT3 : out std_ulogic;
      CLKOUT3B : out std_ulogic;
      CLKOUT4 : out std_ulogic;
      CLKOUT5 : out std_ulogic;
      CLKOUT6 : out std_ulogic;
      LOCKED : out std_ulogic;
      CLKFBIN : in std_ulogic;
      CLKIN1 : in std_ulogic;
      PWRDWN : in std_ulogic;
      RST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    MMCM_BASE : component is "PRIMITIVE";

  component DCM_SP
    generic (
      CLKDV_DIVIDE : real := 2.0;
      CLKFX_DIVIDE : integer := 1;
      CLKFX_MULTIPLY : integer := 4;
      CLKIN_DIVIDE_BY_2 : boolean := false;
      CLKIN_PERIOD : real := 10.0;
      CLKOUT_PHASE_SHIFT : string := "NONE";
      CLK_FEEDBACK : string := "1X";
      DESKEW_ADJUST : string := "SYSTEM_SYNCHRONOUS";
      DFS_FREQUENCY_MODE : string := "LOW";
      DLL_FREQUENCY_MODE : string := "LOW";
      DSS_MODE : string := "NONE";
      DUTY_CYCLE_CORRECTION : boolean := true;
      FACTORY_JF : bit_vector := X"C080";
      PHASE_SHIFT : integer := 0;
      STARTUP_WAIT : boolean := false
      );
    port (
      CLK0 : out std_ulogic := '0';
      CLK180 : out std_ulogic := '0';
      CLK270 : out std_ulogic := '0';
      CLK2X : out std_ulogic := '0';
      CLK2X180 : out std_ulogic := '0';
      CLK90 : out std_ulogic := '0';
      CLKDV : out std_ulogic := '0';
      CLKFX : out std_ulogic := '0';
      CLKFX180 : out std_ulogic := '0';
      LOCKED : out std_ulogic := '0';
      PSDONE : out std_ulogic := '0';
      STATUS : out std_logic_vector(7 downto 0) := "00000000";
      CLKFB : in std_ulogic := '0';
      CLKIN : in std_ulogic := '0';
      DSSEN : in std_ulogic := '0';
      PSCLK : in std_ulogic := '0';
      PSEN : in std_ulogic := '0';
      PSINCDEC : in std_ulogic := '0';
      RST : in std_ulogic := '0'
      );
  end component;
  attribute BOX_TYPE of
    DCM_SP : component is "PRIMITIVE";

  type params is
  record
    vco_freq : integer;
    fin_factor : integer;
    fout_factor : integer;
  end record;
  
  function pll_params_calc(fin, fout : integer;
                           mode: pll_variant) return params
  is
    constant bounds : constraints := constraints_get(mode);
    variable freq_lcm, vco_mult : integer;
    variable ret : params;
  begin
    freq_lcm := nsl_math.arith.lcm(fin, fout);

    vco_mult := integer(trunc(realmin(
      real(bounds.fmax) / real(freq_lcm),
      real(bounds.in_factor_max) * real(fin) / real(freq_lcm)
      )));
    if vco_mult = 0 then
      vco_mult := 1;
    end if;

    ret.vco_freq := freq_lcm * vco_mult;
    ret.fin_factor := ret.vco_freq / fin;
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

  constant series67_params : string := str_param_extract(hw_variant_c, "series67");
  constant variant : pll_variant := variant_get(series67_params);

  signal s_reset : std_ulogic;
  
begin

  s_reset <= not reset_n_i;

  passthrough: if input_hz_c = output_hz_c
  generate
    clock_o <= clock_i;
    locked_o <= reset_n_i;
  end generate;

  use_s6pll: if variant = S6_PLL and input_hz_c /= output_hz_c
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(input_hz_c, output_hz_c, variant);
    signal s_feedback : std_ulogic;
  begin
    
    pll_inst: pll_base
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

  use_s7pll: if variant = S7_PLL and input_hz_c /= output_hz_c
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(input_hz_c, output_hz_c, variant);
    signal s_feedback : std_ulogic;
  begin
    
    pll_inst: plle2_adv
      generic map (
        divclk_divide        => 1,
        clkfbout_mult        => p.fin_factor,
        clkout0_divide       => p.fout_factor,
        clkin1_period        => input_period_ns_c,
        ref_jitter1          => 0.125
        )
      port map (
        rst                 => s_reset,
        clkin1              => clock_i,
        clkin2              => '0',
        clkinsel            => '1',

        clkout0             => clock_o,
        locked              => locked_o,

        daddr => "0000000",
        dclk => '0',
        den => '0',
        di => x"0000",
        dwe => '0',

        pwrdwn => '0',
        
        clkfbin             => s_feedback,
        clkfbout            => s_feedback
        );
  end generate;

  use_s7mmcm: if variant = S7_MMCM and input_hz_c /= output_hz_c
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(input_hz_c, output_hz_c, variant);
    signal s_feedback : std_ulogic;
  begin
    
    mmcm_inst: mmcm_base
      generic map (
        divclk_divide        => 1,
        clkfbout_mult_f      => real(p.fin_factor),
        clkout0_divide_f     => real(p.fout_factor),
        clkin1_period        => input_period_ns_c,
        ref_jitter1          => 0.125
        )
      port map (
        rst                 => s_reset,
        pwrdwn              => '0',
        clkin1              => clock_i,

        clkout0             => clock_o,
        locked              => locked_o,

        clkfbin             => s_feedback,
        clkfbout            => s_feedback
        );
  end generate;

  use_s6dcm: if variant = S6_DCM and input_hz_c /= output_hz_c
  generate
    constant input_period_ns_c : real := 1.0e9 / real(input_hz_c);

    constant p : params := pll_params_calc(input_hz_c, output_hz_c, variant);
    signal s_feedback : std_ulogic;
    constant is_d2 : boolean := p.fin_factor = 1;
  begin
    
    dcm_inst: dcm_sp
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
