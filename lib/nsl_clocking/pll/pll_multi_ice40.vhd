library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.text.all;
use work.pll.all;


-- Realized on SB_PLL40 in SIMPLE feedback mode, single output.
--
-- The config's reference_input picks the primitive: PAD (the
-- default) is SB_PLL40_PAD, whose clock_i must be the package pin
-- itself, CORE is SB_PLL40_CORE, fed from fabric.  The output's
-- routing picks the port it leaves on, GLOBAL (the default) or
-- CORE.
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

architecture ice40 of pll_multi is

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);

  function log2(value: positive) return natural
  is
    variable v: positive := value;
    variable ret: natural := 0;
  begin
    while v > 1 loop
      assert v mod 2 = 0
        report "Divisor is not a power of two"
        severity failure;
      v := v / 2;
      ret := ret + 1;
    end loop;
    return ret;
  end function;

  -- From the SB_PLL40 datasheet, indexed by phase detector rate.
  function filter_range(pfd_khz: natural) return natural
  is
  begin
    if pfd_khz < 17_000 then
      return 1;
    elsif pfd_khz < 26_000 then
      return 2;
    elsif pfd_khz < 44_000 then
      return 3;
    elsif pfd_khz < 66_000 then
      return 4;
    elsif pfd_khz < 101_000 then
      return 5;
    end if;
    return 6;
  end function;

  constant use_core_in_c : boolean
    := config_c.reference_input = work.pll_backend.pll_reference_id("CORE");
  constant use_core_out_c : boolean
    := config_c.output(0).routing = work.pll_backend.pll_routing_id("CORE");

  constant divr_c : std_logic_vector(3 downto 0)
    := std_logic_vector(to_unsigned(mapping_c.refdiv - 1, 4));
  constant divf_c : std_logic_vector(6 downto 0)
    := std_logic_vector(to_unsigned(mapping_c.fbdiv.num - 1, 7));
  constant divq_c : std_logic_vector(2 downto 0)
    := std_logic_vector(to_unsigned(log2(mapping_c.output(0).divisor.num), 3));
  constant filter_range_c : std_logic_vector(2 downto 0)
    := std_logic_vector(to_unsigned(filter_range(mapping_c.pfd_khz), 3));

  signal clkout_core_s, clkout_global_s : std_ulogic;

  component SB_PLL40_CORE is
    generic (
      FEEDBACK_PATH : string := "SIMPLE";
      DELAY_ADJUSTMENT_MODE_FEEDBACK : string := "FIXED";
      DELAY_ADJUSTMENT_MODE_RELATIVE : string := "FIXED";
      SHIFTREG_DIV_MODE : std_logic_vector(1 downto 0) := "00";
      FDA_FEEDBACK : std_logic_vector(3 downto 0) := "0000";
      FDA_RELATIVE : std_logic_vector(3 downto 0) := "0000";
      PLLOUT_SELECT : string := "GENCLK";
      DIVF : std_logic_vector(6 downto 0);
      DIVR : std_logic_vector(3 downto 0);
      DIVQ : std_logic_vector(2 downto 0);
      FILTER_RANGE : std_logic_vector(2 downto 0);
      ENABLE_ICEGATE : bit := '0';
      TEST_MODE : bit := '0';
      EXTERNAL_DIVIDE_FACTOR : integer := 1
      );
    port (
      REFERENCECLK : in std_logic;
      PLLOUTCORE : out std_logic;
      PLLOUTGLOBAL : out std_logic;
      EXTFEEDBACK : in std_logic;
      DYNAMICDELAY : in std_logic_vector (7 downto 0);
      LOCK : out std_logic;
      BYPASS : in std_logic;
      RESETB : in std_logic;
      LATCHINPUTVALUE : in std_logic;
      SDO : out std_logic;
      SDI : in std_logic;
      SCLK : in std_logic
      );
  end component;

  component SB_PLL40_PAD is
    generic (
      FEEDBACK_PATH : string := "SIMPLE";
      DELAY_ADJUSTMENT_MODE_FEEDBACK : string := "FIXED";
      DELAY_ADJUSTMENT_MODE_RELATIVE : string := "FIXED";
      SHIFTREG_DIV_MODE : std_logic_vector(1 downto 0) := "00";
      FDA_FEEDBACK : std_logic_vector(3 downto 0) := "0000";
      FDA_RELATIVE : std_logic_vector(3 downto 0) := "0000";
      PLLOUT_SELECT : string := "GENCLK";
      DIVF : std_logic_vector(6 downto 0);
      DIVR : std_logic_vector(3 downto 0);
      DIVQ : std_logic_vector(2 downto 0);
      FILTER_RANGE : std_logic_vector(2 downto 0);
      ENABLE_ICEGATE : bit := '0';
      TEST_MODE : bit := '0';
      EXTERNAL_DIVIDE_FACTOR : integer := 1
      );
    port (
      PACKAGEPIN : in std_logic;
      PLLOUTCORE : out std_logic;
      PLLOUTGLOBAL : out std_logic;
      EXTFEEDBACK : in std_logic;
      DYNAMICDELAY : in std_logic_vector (7 downto 0);
      LOCK : out std_logic;
      BYPASS : in std_logic;
      RESETB : in std_logic;
      LATCHINPUTVALUE : in std_logic;
      SDO : out std_logic;
      SDI : in std_logic;
      SCLK : in std_logic
      );
  end component;

begin


  assert false
    report "iCE40 PLL: " & to_string(mapping_c)
    severity note;

  use_core: if use_core_in_c generate
    inst: sb_pll40_core
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        referenceclk => clock_i,
        plloutcore => clkout_core_s,
        plloutglobal => clkout_global_s,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;

  use_pad: if not use_core_in_c generate
    inst: sb_pll40_pad
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        packagepin => clock_i,
        plloutcore => clkout_core_s,
        plloutglobal => clkout_global_s,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;

  out_core: if use_core_out_c generate
    clock_o(0) <= clkout_core_s;
  end generate;

  out_global: if not use_core_out_c generate
    clock_o(0) <= clkout_global_s;
  end generate;

end architecture ice40;
