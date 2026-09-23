library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.text.all;
use work.pll.all;

-- Realized on the tennm_ph2_iopll atom.  This family has no
-- megafunction taking a ratio the way ALTPLL does: the IOPLL IP is a
-- Platform Designer generator whose output instantiates this same
-- atom with the counters it chose, so here the solver's N, M and C
-- are what the fitter builds, and the frequency generics beside them
-- are the rates those counters give.
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

architecture agilex5 of pll_multi is

  -- Quartus requires every generic of the atom to be given.  Values
  -- follow what the IOPLL generator emits for a standalone, directly
  -- compensated, integer PLL with no reconfiguration; only the ports
  -- this design drives are declared.
  component tennm_ph2_iopll is
    generic (
      bandwidth_mode : string := "BANDWIDTH_MODE_AUTO";
      base_address : std_logic_vector(10 downto 0) := (others => '0');
      cascade_mode : string := "CASCADE_MODE_DOWNSTREAM";
      clk_switch_auto_en : string := "FALSE";
      clk_switch_manual_en : string := "FALSE";
      compensation_clk_source : string := "COMPENSATION_CLK_SOURCE_EXTCLK0";
      compensation_mode : string := "COMPENSATION_MODE_DIRECT";
      fb_clk_delay : integer := 0;
      fb_clk_fractional_div_den : integer := 0;
      fb_clk_fractional_div_num : integer := 0;
      fb_clk_fractional_div_value : integer := 0;
      fb_clk_m_div : integer := 0;
      out_clk_0_c_div : integer := 0;
      out_clk_0_core_en : string := "FALSE";
      out_clk_0_delay : integer := 0;
      out_clk_0_dutycycle_den : integer := 0;
      out_clk_0_dutycycle_num : integer := 0;
      out_clk_0_dutycycle_percent : integer := 0;
      out_clk_0_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_0_phase_ps : integer := 0;
      out_clk_0_phase_shifts : integer := 0;
      out_clk_1_c_div : integer := 0;
      out_clk_1_core_en : string := "FALSE";
      out_clk_1_delay : integer := 0;
      out_clk_1_dutycycle_den : integer := 0;
      out_clk_1_dutycycle_num : integer := 0;
      out_clk_1_dutycycle_percent : integer := 0;
      out_clk_1_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_1_phase_ps : integer := 0;
      out_clk_1_phase_shifts : integer := 0;
      out_clk_2_c_div : integer := 0;
      out_clk_2_core_en : string := "FALSE";
      out_clk_2_delay : integer := 0;
      out_clk_2_dutycycle_den : integer := 0;
      out_clk_2_dutycycle_num : integer := 0;
      out_clk_2_dutycycle_percent : integer := 0;
      out_clk_2_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_2_phase_ps : integer := 0;
      out_clk_2_phase_shifts : integer := 0;
      out_clk_3_c_div : integer := 0;
      out_clk_3_core_en : string := "FALSE";
      out_clk_3_delay : integer := 0;
      out_clk_3_dutycycle_den : integer := 0;
      out_clk_3_dutycycle_num : integer := 0;
      out_clk_3_dutycycle_percent : integer := 0;
      out_clk_3_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_3_phase_ps : integer := 0;
      out_clk_3_phase_shifts : integer := 0;
      out_clk_4_c_div : integer := 0;
      out_clk_4_core_en : string := "FALSE";
      out_clk_4_delay : integer := 0;
      out_clk_4_dutycycle_den : integer := 0;
      out_clk_4_dutycycle_num : integer := 0;
      out_clk_4_dutycycle_percent : integer := 0;
      out_clk_4_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_4_phase_ps : integer := 0;
      out_clk_4_phase_shifts : integer := 0;
      out_clk_5_c_div : integer := 0;
      out_clk_5_core_en : string := "FALSE";
      out_clk_5_delay : integer := 0;
      out_clk_5_dutycycle_den : integer := 0;
      out_clk_5_dutycycle_num : integer := 0;
      out_clk_5_dutycycle_percent : integer := 0;
      out_clk_5_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_5_phase_ps : integer := 0;
      out_clk_5_phase_shifts : integer := 0;
      out_clk_6_c_div : integer := 0;
      out_clk_6_core_en : string := "FALSE";
      out_clk_6_delay : integer := 0;
      out_clk_6_dutycycle_den : integer := 0;
      out_clk_6_dutycycle_num : integer := 0;
      out_clk_6_dutycycle_percent : integer := 0;
      out_clk_6_freq : std_logic_vector(35 downto 0) := (others => '0');
      out_clk_6_phase_ps : integer := 0;
      out_clk_6_phase_shifts : integer := 0;
      out_clk_cascading_source : string := "OUT_CLK_CASCADING_SOURCE_OUTCLK0";
      out_clk_external_0_source : string := "OUT_CLK_EXTERNAL_0_SOURCE_FBCLK";
      out_clk_external_1_source : string := "OUT_CLK_EXTERNAL_1_SOURCE_FBCLK";
      out_clk_periph_0_delay : integer := 0;
      out_clk_periph_0_en : string := "FALSE";
      out_clk_periph_1_delay : integer := 0;
      out_clk_periph_1_en : string := "FALSE";
      pfd_clk_freq : std_logic_vector(31 downto 0) := (others => '0');
      protocol_mode : string := "PROTOCOL_MODE_BASIC";
      ref_clk_0_freq : std_logic_vector(31 downto 0) := (others => '0');
      ref_clk_1_freq : std_logic_vector(31 downto 0) := (others => '0');
      ref_clk_delay : integer := 0;
      ref_clk_n_div : integer := 0;
      self_reset_en : string := "FALSE";
      set_dutycycle : string := "SET_DUTYCYCLE_FRACTION";
      set_fractional : string := "SET_FRACTIONAL_FRACTION";
      set_freq : string := "SET_FREQ_DIVISION";
      set_phase : string := "SET_PHASE_NUM_SHIFTS";
      vco_clk_freq : std_logic_vector(35 downto 0) := (others => '0')
      );
    port (
      lock : out std_logic;
      out_clk : out std_logic_vector(6 downto 0);
      permit_cal : in std_logic := '0';
      ref_clk0 : in std_logic := '0';
      reset : in std_logic := '0'
      );
  end component;

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);

  constant output_mapping_none_c : pll_output_mapping_t := (
    enabled => false,
    port_index => 0,
    divisor => pll_ratio_one_c,
    hz => 0,
    exact => false,
    phase => pll_ratio_zero_c);

  -- Realization parameters of the output carried by one physical
  -- port.  A port no logical output landed on is left bypassed and
  -- disabled, as the generator leaves it.
  function port_mapping(p: natural) return pll_output_mapping_t
  is
  begin
    for i in 0 to mapping_c.output_count - 1 loop
      if mapping_c.output(i).enabled
        and mapping_c.output(i).port_index = p then
        return mapping_c.output(i);
      end if;
    end loop;
    return output_mapping_none_c;
  end function;

  -- VCO rate in Hz, reference times M over N.  It overflows an
  -- integer, hence the vector.
  function vco_hz return unsigned
  is
  begin
    return resize(to_unsigned(config_c.input_hz, 32)
                  * to_unsigned(mapping_c.fbdiv.num, 16), 48)
      / to_unsigned(mapping_c.refdiv, 16);
  end function;

  function c_div(p: natural) return integer
  is
    constant m: pll_output_mapping_t := port_mapping(p);
  begin
    return m.divisor.num / m.divisor.den;
  end function;

  function core_en(p: natural) return string
  is
  begin
    if port_mapping(p).enabled then
      return "TRUE";
    end if;
    return "FALSE";
  end function;

  -- A 50% duty cycle as the generator states it: high half of the
  -- counter over twice the counter, which for any C is C over 2C,
  -- except that a bypassed counter is stated as 2 over 4.
  function duty_num(p: natural) return integer
  is
  begin
    if c_div(p) = 1 then
      return 2;
    end if;
    return c_div(p);
  end function;

  function duty_den(p: natural) return integer
  is
  begin
    return 2 * duty_num(p);
  end function;

  function out_hz(p: natural) return std_logic_vector
  is
  begin
    return std_logic_vector(resize(vco_hz / to_unsigned(c_div(p), 16), 36));
  end function;

  -- Phase shift of the output carried by port p, in eighths of a VCO
  -- cycle.  A phase is stated as a fraction of the output cycle, and
  -- an output cycle is C VCO cycles, so the eighths come out as
  -- phase * 8 * C -- a whole number, the solver having refused
  -- anything off that grid.
  function phase_shifts(p: natural) return integer
  is
    constant m: pll_output_mapping_t := port_mapping(p);
  begin
    if m.phase.num = 0 then
      return 0;
    end if;
    return (m.phase.num * 8 * c_div(p)) / m.phase.den;
  end function;

  function phase_ps(p: natural) return integer
  is
  begin
    return integer(real(phase_shifts(p)) * 1.0e12
                   / (8.0 * real(config_c.input_hz)
                      * real(mapping_c.fbdiv.num) / real(mapping_c.refdiv)));
  end function;

  signal out_clk_s : std_logic_vector(6 downto 0);
  signal lock_s, reset_s : std_logic;

begin

  assert false
    report "Agilex 5 PLL: " & to_string(mapping_c)
    severity note;

  reset_s <= not reset_n_i;

  inst: tennm_ph2_iopll
    generic map(
      bandwidth_mode => "BANDWIDTH_MODE_AUTO",
      base_address => (others => '0'),
      cascade_mode => "CASCADE_MODE_STANDALONE",
      clk_switch_auto_en => "FALSE",
      clk_switch_manual_en => "FALSE",
      compensation_clk_source => "COMPENSATION_CLK_SOURCE_UNUSED",
      compensation_mode => "COMPENSATION_MODE_DIRECT",
      fb_clk_delay => 0,
      fb_clk_fractional_div_den => 1,
      fb_clk_fractional_div_num => 1,
      fb_clk_fractional_div_value => 1,
      fb_clk_m_div => mapping_c.fbdiv.num,
      out_clk_0_c_div => c_div(0),
      out_clk_0_core_en => core_en(0),
      out_clk_0_delay => 0,
      out_clk_0_dutycycle_den => duty_den(0),
      out_clk_0_dutycycle_num => duty_num(0),
      out_clk_0_dutycycle_percent => 50,
      out_clk_0_freq => out_hz(0),
      out_clk_0_phase_ps => phase_ps(0),
      out_clk_0_phase_shifts => phase_shifts(0),
      out_clk_1_c_div => c_div(1),
      out_clk_1_core_en => core_en(1),
      out_clk_1_delay => 0,
      out_clk_1_dutycycle_den => duty_den(1),
      out_clk_1_dutycycle_num => duty_num(1),
      out_clk_1_dutycycle_percent => 50,
      out_clk_1_freq => out_hz(1),
      out_clk_1_phase_ps => phase_ps(1),
      out_clk_1_phase_shifts => phase_shifts(1),
      out_clk_2_c_div => c_div(2),
      out_clk_2_core_en => core_en(2),
      out_clk_2_delay => 0,
      out_clk_2_dutycycle_den => duty_den(2),
      out_clk_2_dutycycle_num => duty_num(2),
      out_clk_2_dutycycle_percent => 50,
      out_clk_2_freq => out_hz(2),
      out_clk_2_phase_ps => phase_ps(2),
      out_clk_2_phase_shifts => phase_shifts(2),
      out_clk_3_c_div => c_div(3),
      out_clk_3_core_en => core_en(3),
      out_clk_3_delay => 0,
      out_clk_3_dutycycle_den => duty_den(3),
      out_clk_3_dutycycle_num => duty_num(3),
      out_clk_3_dutycycle_percent => 50,
      out_clk_3_freq => out_hz(3),
      out_clk_3_phase_ps => phase_ps(3),
      out_clk_3_phase_shifts => phase_shifts(3),
      out_clk_4_c_div => c_div(4),
      out_clk_4_core_en => core_en(4),
      out_clk_4_delay => 0,
      out_clk_4_dutycycle_den => duty_den(4),
      out_clk_4_dutycycle_num => duty_num(4),
      out_clk_4_dutycycle_percent => 50,
      out_clk_4_freq => out_hz(4),
      out_clk_4_phase_ps => phase_ps(4),
      out_clk_4_phase_shifts => phase_shifts(4),
      out_clk_5_c_div => c_div(5),
      out_clk_5_core_en => core_en(5),
      out_clk_5_delay => 0,
      out_clk_5_dutycycle_den => duty_den(5),
      out_clk_5_dutycycle_num => duty_num(5),
      out_clk_5_dutycycle_percent => 50,
      out_clk_5_freq => out_hz(5),
      out_clk_5_phase_ps => phase_ps(5),
      out_clk_5_phase_shifts => phase_shifts(5),
      out_clk_6_c_div => c_div(6),
      out_clk_6_core_en => core_en(6),
      out_clk_6_delay => 0,
      out_clk_6_dutycycle_den => duty_den(6),
      out_clk_6_dutycycle_num => duty_num(6),
      out_clk_6_dutycycle_percent => 50,
      out_clk_6_freq => out_hz(6),
      out_clk_6_phase_ps => phase_ps(6),
      out_clk_6_phase_shifts => phase_shifts(6),
      out_clk_cascading_source => "OUT_CLK_CASCADING_SOURCE_UNUSED",
      out_clk_external_0_source => "OUT_CLK_EXTERNAL_0_SOURCE_UNUSED",
      out_clk_external_1_source => "OUT_CLK_EXTERNAL_1_SOURCE_UNUSED",
      out_clk_periph_0_delay => 0,
      out_clk_periph_0_en => "TRUE",
      out_clk_periph_1_delay => 0,
      out_clk_periph_1_en => "TRUE",
      pfd_clk_freq => std_logic_vector(to_unsigned(mapping_c.pfd_khz * 1000, 32)),
      protocol_mode => "PROTOCOL_MODE_BASIC",
      ref_clk_0_freq => std_logic_vector(to_unsigned(config_c.input_hz, 32)),
      ref_clk_1_freq => (others => '0'),
      ref_clk_delay => 0,
      ref_clk_n_div => mapping_c.refdiv,
      self_reset_en => "TRUE",
      set_dutycycle => "SET_DUTYCYCLE_FRACTION",
      set_fractional => "SET_FRACTIONAL_FRACTION",
      set_freq => "SET_FREQ_DIVISION_VERIFY",
      set_phase => "SET_PHASE_NUM_SHIFTS_VERIFY",
      vco_clk_freq => std_logic_vector(resize(vco_hz, 36))
      )
    port map(
      lock => lock_s,
      out_clk => out_clk_s,
      permit_cal => '1',
      ref_clk0 => clock_i,
      reset => reset_s
      );

  locked_o <= lock_s;

  outputs: for i in 0 to config_c.output_count - 1 generate
    clock_o(i) <= out_clk_s(mapping_c.output(i).port_index);
  end generate;

end architecture agilex5;
