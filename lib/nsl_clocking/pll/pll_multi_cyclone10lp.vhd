library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.text.all;
use work.pll.all;

-- Realized on the ALTPLL megafunction rather than on the
-- cyclone10lp_pll atom underneath it.  The atom takes the counters
-- already encoded -- high and low half periods, initial value, even
-- or odd mode, VCO phase tap -- together with the charge pump
-- current and loop filter settings the VCO rate calls for.  Those
-- encodings are neither documented nor stable across the family, and
-- a wrong loop filter builds a PLL that elaborates and locks badly.
-- ALTPLL derives all of them from the rates, is the interface Intel
-- documents, and carries the same shape on Cyclone IV E and MAX 10,
-- so this architecture moves to those families by widening the
-- topology, not by being rewritten.
--
-- What this means for the split of work: the solver settles the
-- rational ratio of every output to the reference and proves a legal
-- N, M and C assignment exists for it.  ALTPLL is handed the ratio,
-- and Quartus picks counter values realizing it, which need not be
-- the ones the mapping names -- 12 MHz to 80 MHz comes out of the
-- solver as M = 100 over C = 15 and out of the fitter as M = 40 over
-- C = 6 with the VCO post-scale counter halving.  Rates are the same
-- either way, since the ratio is exact; the counters in the mapping
-- are what makes the request feasible, not what the fitter ends up
-- building.
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

architecture cyclone10lp of pll_multi is

  -- Only the generics and ports this design drives.  Everything left
  -- out defaults in the megafunction: inputs hold a safe value,
  -- outputs stay open.  inclk0_input_frequency has no default there
  -- and is the reference period in picoseconds.
  component altpll is
    generic (
      intended_device_family : string := "Cyclone 10 LP";
      lpm_type : string := "altpll";
      operation_mode : string := "NORMAL";
      pll_type : string := "AUTO";
      inclk0_input_frequency : natural;
      width_clock : natural := 6;
      port_inclk0 : string := "PORT_CONNECTIVITY";
      port_inclk1 : string := "PORT_CONNECTIVITY";
      port_areset : string := "PORT_CONNECTIVITY";
      port_locked : string := "PORT_CONNECTIVITY";
      port_clk0 : string := "PORT_CONNECTIVITY";
      port_clk1 : string := "PORT_CONNECTIVITY";
      port_clk2 : string := "PORT_CONNECTIVITY";
      port_clk3 : string := "PORT_CONNECTIVITY";
      port_clk4 : string := "PORT_CONNECTIVITY";
      clk0_multiply_by : natural := 1;
      clk1_multiply_by : natural := 1;
      clk2_multiply_by : natural := 1;
      clk3_multiply_by : natural := 1;
      clk4_multiply_by : natural := 1;
      clk0_divide_by : natural := 1;
      clk1_divide_by : natural := 1;
      clk2_divide_by : natural := 1;
      clk3_divide_by : natural := 1;
      clk4_divide_by : natural := 1;
      clk0_duty_cycle : natural := 50;
      clk1_duty_cycle : natural := 50;
      clk2_duty_cycle : natural := 50;
      clk3_duty_cycle : natural := 50;
      clk4_duty_cycle : natural := 50
      );
    port (
      inclk : in std_logic_vector(1 downto 0) := (others => '0');
      areset : in std_logic := '0';
      clk : out std_logic_vector(width_clock-1 downto 0);
      locked : out std_logic
      );
  end component;

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);

  -- Reference period in picoseconds, what ALTPLL states the input
  -- rate with.  Only used by Quartus to check the request against
  -- the block's frequency windows and to report rates: output rates
  -- come from the ratios below, so rounding here does not reach
  -- them.
  constant input_ps_c : natural := natural(1.0e12 / real(config_c.input_hz));

  constant output_mapping_none_c : pll_output_mapping_t := (
    enabled => false,
    port_index => 0,
    divisor => pll_ratio_one_c,
    hz => 0,
    exact => false,
    phase => pll_ratio_zero_c);

  -- Realization parameters of the output carried by one physical
  -- port.  A port no logical output landed on stays disabled.
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

  -- Rate of physical port p over the reference rate, in lowest
  -- terms.  The mapping states it as M / (N * K * C).
  function port_ratio(p: natural) return pll_ratio_t
  is
    constant om_c: pll_output_mapping_t := port_mapping(p);
    variable num, den, g: positive;
  begin
    if not om_c.enabled then
      return pll_ratio_one_c;
    end if;
    num := mapping_c.fbdiv.num * om_c.divisor.den;
    den := mapping_c.refdiv * mapping_c.postdiv
      * om_c.divisor.num * mapping_c.fbdiv.den;
    g := gcd(num, den);
    return (num => num / g, den => den / g);
  end function;

  function multiplier(p: natural) return natural
  is
  begin
    return port_ratio(p).num;
  end function;

  function divisor(p: natural) return natural
  is
  begin
    return port_ratio(p).den;
  end function;

  function port_use(p: natural) return string
  is
  begin
    if port_mapping(p).enabled then
      return "PORT_USED";
    end if;
    return "PORT_UNUSED";
  end function;

  signal clk_s : std_logic_vector(4 downto 0);
  signal inclk_s : std_logic_vector(1 downto 0);

begin

  assert false
    report "Cyclone 10 LP PLL: " & to_string(mapping_c)
    severity note;

  inclk_s(0) <= clock_i;
  inclk_s(1) <= '0';

  -- No compensation: this abstraction promises rates and the phase
  -- of outputs relative to each other, never a phase relation to the
  -- reference.  Normal mode would promise the latter at the cost of
  -- failing the fitter whenever the compensated output does not
  -- reach a global clock network.
  inst: altpll
    generic map(
      intended_device_family => "Cyclone 10 LP",
      lpm_type => "altpll",
      operation_mode => "NO_COMPENSATION",
      pll_type => "AUTO",
      inclk0_input_frequency => input_ps_c,
      width_clock => 5,
      port_inclk0 => "PORT_USED",
      port_inclk1 => "PORT_UNUSED",
      port_areset => "PORT_USED",
      port_locked => "PORT_USED",
      port_clk0 => port_use(0),
      port_clk1 => port_use(1),
      port_clk2 => port_use(2),
      port_clk3 => port_use(3),
      port_clk4 => port_use(4),
      clk0_multiply_by => multiplier(0),
      clk1_multiply_by => multiplier(1),
      clk2_multiply_by => multiplier(2),
      clk3_multiply_by => multiplier(3),
      clk4_multiply_by => multiplier(4),
      clk0_divide_by => divisor(0),
      clk1_divide_by => divisor(1),
      clk2_divide_by => divisor(2),
      clk3_divide_by => divisor(3),
      clk4_divide_by => divisor(4),
      clk0_duty_cycle => 50,
      clk1_duty_cycle => 50,
      clk2_duty_cycle => 50,
      clk3_duty_cycle => 50,
      clk4_duty_cycle => 50
      )
    port map(
      inclk => inclk_s,
      areset => "not"(reset_n_i),
      clk => clk_s,
      locked => locked_o
      );

  outputs: for i in 0 to config_c.output_count - 1 generate
    clock_o(i) <= clk_s(mapping_c.output(i).port_index);
  end generate;

end architecture cyclone10lp;
