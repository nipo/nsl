library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_logic, nsl_data;
use nsl_logic.bool.all;
use nsl_data.text.all;
use work.pll.all;
use work.pll_config_series67.all;

-- Realized on the clock manager the config's implementation names:
-- PLL_BASE on Spartan-6, PLLE2_ADV or MMCM_BASE on Series-7, all fed
-- back through CLKFBOUT with the input divider at 1, or DCM_SP,
-- whose multiplier and divider are the feedback and output divisors
-- of the model.
entity pll_multi is
  generic(
    config_c : pll_config_t
    );
  port(
    clock_i : in std_ulogic;
    clock_o : out std_ulogic_vector(0 to config_c.output_count-1);

    reset_n_i : in std_ulogic;
    locked_o : out std_ulogic
    );
end entity;

architecture series67 of pll_multi is

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


  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);
  constant variant_c : pll_variant := variant_of_id(config_c.implementation);
  constant input_period_ns_c : real := 1.0e9 / real(config_c.input_hz);

  -- Realization parameters of the output carried by one physical
  -- port.  Unused ports divide by one and are left unconnected.
  function port_mapping(p: natural) return pll_output_mapping_t
  is
  begin
    for i in 0 to mapping_c.output_count - 1 loop
      if mapping_c.output(i).enabled
        and mapping_c.output(i).port_index = p then
        return mapping_c.output(i);
      end if;
    end loop;
    return (enabled => false,
            port_index => 0,
            divisor => pll_ratio_one_c,
            hz => 0,
            exact => false,
            phase => pll_ratio_zero_c);
  end function;

  function odiv(p: natural) return integer
  is
  begin
    return port_mapping(p).divisor.num;
  end function;

  signal reset_s, feedback_s : std_ulogic;
  signal clkout_s : std_ulogic_vector(0 to 5);

begin


  assert false
    report "Series-6/7 PLL: " & to_string(mapping_c)
    severity note;

  reset_s <= not reset_n_i;

  use_s6pll: if variant_c = S6_PLL generate
    inst: pll_base
      generic map (
        clk_feedback => "CLKFBOUT",
        divclk_divide => mapping_c.refdiv,
        clkfbout_mult => mapping_c.fbdiv.num,
        clkout0_divide => odiv(0),
        clkout1_divide => odiv(1),
        clkout2_divide => odiv(2),
        clkout3_divide => odiv(3),
        clkout4_divide => odiv(4),
        clkout5_divide => odiv(5),
        clkin_period => input_period_ns_c,
        ref_jitter => 0.125
        )
      port map (
        rst => reset_s,
        clkin => clock_i,
        clkout0 => clkout_s(0),
        clkout1 => clkout_s(1),
        clkout2 => clkout_s(2),
        clkout3 => clkout_s(3),
        clkout4 => clkout_s(4),
        clkout5 => clkout_s(5),
        locked => locked_o,
        clkfbin => feedback_s,
        clkfbout => feedback_s
        );
  end generate;

  use_s7pll: if variant_c = S7_PLL generate
    inst: plle2_adv
      generic map (
        divclk_divide => mapping_c.refdiv,
        clkfbout_mult => mapping_c.fbdiv.num,
        clkout0_divide => odiv(0),
        clkout1_divide => odiv(1),
        clkout2_divide => odiv(2),
        clkout3_divide => odiv(3),
        clkout4_divide => odiv(4),
        clkout5_divide => odiv(5),
        clkin1_period => input_period_ns_c,
        ref_jitter1 => 0.125
        )
      port map (
        rst => reset_s,
        clkin1 => clock_i,
        clkin2 => '0',
        clkinsel => '1',
        clkout0 => clkout_s(0),
        clkout1 => clkout_s(1),
        clkout2 => clkout_s(2),
        clkout3 => clkout_s(3),
        clkout4 => clkout_s(4),
        clkout5 => clkout_s(5),
        locked => locked_o,
        daddr => "0000000",
        dclk => '0',
        den => '0',
        di => x"0000",
        dwe => '0',
        pwrdwn => '0',
        clkfbin => feedback_s,
        clkfbout => feedback_s
        );
  end generate;

  use_s7mmcm: if variant_c = S7_MMCM generate
    inst: mmcm_base
      generic map (
        divclk_divide => mapping_c.refdiv,
        clkfbout_mult_f => real(mapping_c.fbdiv.num),
        clkout0_divide_f => real(odiv(0)),
        clkout1_divide => odiv(1),
        clkout2_divide => odiv(2),
        clkout3_divide => odiv(3),
        clkout4_divide => odiv(4),
        clkout5_divide => odiv(5),
        clkin1_period => input_period_ns_c,
        ref_jitter1 => 0.125
        )
      port map (
        rst => reset_s,
        pwrdwn => '0',
        clkin1 => clock_i,
        clkout0 => clkout_s(0),
        clkout1 => clkout_s(1),
        clkout2 => clkout_s(2),
        clkout3 => clkout_s(3),
        clkout4 => clkout_s(4),
        clkout5 => clkout_s(5),
        locked => locked_o,
        clkfbin => feedback_s,
        clkfbout => feedback_s
        );
  end generate;

  use_s6dcm: if variant_c = S6_DCM generate
    -- A DCM cannot multiply by one, so a unit feedback factor is
    -- realized as halving the input and multiplying by two.
    constant halve_c : boolean := mapping_c.fbdiv.num = 1;
  begin
    inst: dcm_sp
      generic map(
        clkin_period => input_period_ns_c,
        clkfx_multiply => if_else(halve_c, 2, mapping_c.fbdiv.num),
        clkin_divide_by_2 => halve_c,
        clkfx_divide => odiv(0)
        )
      port map(
        clkin => clock_i,
        rst => reset_s,
        clkfx => clkout_s(0),
        locked => locked_o
        );
  end generate;

  outputs: for i in 0 to config_c.output_count - 1 generate
    clock_o(i) <= clkout_s(mapping_c.output(i).port_index);
  end generate;

end architecture series67;
