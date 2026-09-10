library ieee;
use ieee.std_logic_1164.all;

library nsl_data;
use nsl_data.text.all;
use work.pll.all;

-- Realized on EHXPLLL with FEEDBK_PATH = "CLKOP": CLKFB_DIV is
-- pinned to 1 and CLKOP_DIV carries the whole VCO multiplier, so
-- CLKOP runs at pfd rate and only closes the loop.  User outputs
-- come from the CLKOS/CLKOS2/CLKOS3 dividers.
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

architecture ecp5 of pll_multi is

  component EHXPLLL is
    generic (
      CLKI_DIV          : integer := 1;
      CLKFB_DIV         : integer := 1;
      CLKOP_DIV         : integer := 8;
      CLKOS_DIV         : integer := 8;
      CLKOS2_DIV        : integer := 8;
      CLKOS3_DIV        : integer := 8;
      CLKOP_ENABLE      : string  := "ENABLED";
      CLKOS_ENABLE      : string  := "DISABLED";
      CLKOS2_ENABLE     : string  := "DISABLED";
      CLKOS3_ENABLE     : string  := "DISABLED";
      CLKOP_CPHASE      : integer := 0;
      CLKOS_CPHASE      : integer := 0;
      CLKOS2_CPHASE     : integer := 0;
      CLKOS3_CPHASE     : integer := 0;
      CLKOP_FPHASE      : integer := 0;
      CLKOS_FPHASE      : integer := 0;
      CLKOS2_FPHASE     : integer := 0;
      CLKOS3_FPHASE     : integer := 0;
      FEEDBK_PATH       : string  := "CLKOP";
      CLKOP_TRIM_POL    : string  := "RISING";
      CLKOP_TRIM_DELAY  : integer := 0;
      CLKOS_TRIM_POL    : string  := "RISING";
      CLKOS_TRIM_DELAY  : integer := 0;
      OUTDIVIDER_MUXA   : string  := "DIVA";
      OUTDIVIDER_MUXB   : string  := "DIVB";
      OUTDIVIDER_MUXC   : string  := "DIVC";
      OUTDIVIDER_MUXD   : string  := "DIVD";
      PLL_LOCK_MODE     : integer := 0;
      STDBY_ENABLE      : string  := "DISABLED";
      REFIN_RESET       : string  := "DISABLED";
      DPHASE_SOURCE     : string  := "DISABLED";
      PLLRST_ENA        : string  := "DISABLED";
      INTFB_WAKE        : string  := "DISABLED"
      );
    port (
      CLKI       : in  std_logic;
      CLKFB      : in  std_logic;
      PHASESEL0  : in  std_logic := '0';
      PHASESEL1  : in  std_logic := '0';
      PHASEDIR   : in  std_logic := '0';
      PHASESTEP  : in  std_logic := '0';
      PHASELOADREG : in std_logic := '0';
      STDBY      : in  std_logic := '0';
      PLLWAKESYNC : in std_logic := '0';
      RST        : in  std_logic := '0';
      ENCLKOP    : in  std_logic := '0';
      ENCLKOS    : in  std_logic := '0';
      ENCLKOS2   : in  std_logic := '0';
      ENCLKOS3   : in  std_logic := '0';
      CLKOP      : out std_logic;
      CLKOS      : out std_logic;
      CLKOS2     : out std_logic;
      CLKOS3     : out std_logic;
      LOCK       : out std_logic;
      INTLOCK    : out std_logic;
      REFCLK     : out std_logic;
      CLKINTFB   : out std_logic
      );
  end component;

  constant mapping_c : pll_mapping_t := mapping_checked(work.pll_backend.pll_solve(config_c), config_c);

  -- Realization parameters of the output carried by one physical
  -- port.  Unused ports get a safe divisor and stay disabled.
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
            divisor => (num => 8, den => 1),
            hz => 0,
            exact => false,
            phase => pll_ratio_zero_c);
  end function;

  function odiv(p: natural) return integer
  is
  begin
    return port_mapping(p).divisor.num;
  end function;

  function en_str(p: natural) return string
  is
  begin
    if port_mapping(p).enabled then
      return "ENABLED";
    end if;
    return "DISABLED";
  end function;

  signal clkop_s : std_logic;
  signal clkout_s : std_ulogic_vector(0 to 2);

begin


  assert false
    report "ECP5 PLL: " & to_string(mapping_c)
    severity note;

  inst: EHXPLLL
    generic map(
      CLKI_DIV      => mapping_c.refdiv,
      CLKFB_DIV     => 1,
      CLKOP_DIV     => mapping_c.fbdiv.num,
      CLKOS_DIV     => odiv(0),
      CLKOS2_DIV    => odiv(1),
      CLKOS3_DIV    => odiv(2),
      CLKOP_ENABLE  => "ENABLED",
      CLKOS_ENABLE  => en_str(0),
      CLKOS2_ENABLE => en_str(1),
      CLKOS3_ENABLE => en_str(2),
      CLKOP_CPHASE  => mapping_c.fbdiv.num - 1,
      CLKOP_FPHASE  => 0,
      FEEDBK_PATH   => "CLKOP",
      OUTDIVIDER_MUXA => "DIVA"
      )
    port map(
      CLKI   => clock_i,
      CLKFB  => clkop_s,
      RST    => "not"(reset_n_i),
      CLKOP  => clkop_s,
      CLKOS  => clkout_s(0),
      CLKOS2 => clkout_s(1),
      CLKOS3 => clkout_s(2),
      LOCK   => locked_o
      );

  outputs: for i in 0 to config_c.output_count - 1 generate
    clock_o(i) <= clkout_s(mapping_c.output(i).port_index);
  end generate;

end architecture ecp5;
