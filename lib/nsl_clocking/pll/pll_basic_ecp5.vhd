library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
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

architecture ecp5 of pll_basic is

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

  -- EHXPLLL operating constraints (post -7/-8 speed grade):
  --   fref = fin / CLKI_DIV         in [8 MHz,   400 MHz]
  --   fvco = fref * CLKFB_DIV *
  --                 CLKOP_DIV       in [400 MHz, 800 MHz]
  --   fout = fvco / CLKOP_DIV       in [3.125 MHz, 400 MHz]
  -- Loop with FEEDBK_PATH = "CLKOP":
  --   fout = fin * CLKFB_DIV / CLKI_DIV
  type ecp5_pll_params is
  record
    clki_div, clkfb_div, clkop_div : integer;
    fref, fout, fvco, err: real;
    found: boolean;
  end record;

  function ecp5_pll_params_generate(fin, fout : integer)
    return ecp5_pll_params
  is
    constant fin_r : real := real(fin);
    constant fout_r : real := real(fout);
    constant fref_min : real := 8.0e6;
    constant fref_max : real := 400.0e6;
    constant fvco_min : real := 400.0e6;
    constant fvco_max : real := 800.0e6;
    variable best, potential : ecp5_pll_params := (1, 1, 8, 0.0, 0.0, 0.0, 100.0e9, false);
  begin
    for clki_div in 128 downto 1 loop
      potential.fref := fin_r / real(clki_div);
      if potential.fref < fref_min or potential.fref > fref_max then
        next;
      end if;

      for clkfb_div in 128 downto 1 loop
        potential.fout := potential.fref * real(clkfb_div);
        potential.err := abs(potential.fout - fout_r);
        if potential.err > best.err then
          next;
        end if;

        for clkop_div in 128 downto 1 loop
          potential.fvco := potential.fout * real(clkop_div);
          if potential.fvco < fvco_min or potential.fvco > fvco_max then
            next;
          end if;

          potential.clki_div := clki_div;
          potential.clkfb_div := clkfb_div;
          potential.clkop_div := clkop_div;
          potential.found := true;
          if best.found and best.err = 0.0 and best.fvco > potential.fvco then
            next;
          end if;
          if best.found and best.err = 0.0 and best.fref > potential.fref then
            next;
          end if;
          best := potential;
        end loop;
      end loop;
    end loop;

    assert best.found
      report "Cannot find an EHXPLLL configuration for fin=" & to_string(fin)
        & " Hz, fout=" & to_string(fout) & " Hz"
      severity failure;

    report "Synthesizing ECP5 PLL, "
      & "fin=" & to_string(fin_r / 1.0e6) & " MHz, "
      & "fout=" & to_string(fout_r / 1.0e6) & " MHz"
      severity note;
    report "Best option: CLKI_DIV=" & to_string(best.clki_div)
      & ", CLKFB_DIV=" & to_string(best.clkfb_div)
      & ", CLKOP_DIV=" & to_string(best.clkop_div)
      & ", fref=" & to_string(best.fref / 1.0e6) & " MHz"
      & ", fvco=" & to_string(best.fvco / 1.0e6) & " MHz"
      & ", fout=" & to_string(best.fout / 1.0e6) & " MHz"
      & ", error=" & to_string(best.err / 1.0e6) & " MHz"
      severity note;

    return best;
  end function;

  constant params : ecp5_pll_params := ecp5_pll_params_generate(input_hz_c, output_hz_c);

  signal clkop_s : std_logic;

begin

  inst: EHXPLLL
    generic map(
      CLKI_DIV     => params.clki_div,
      CLKFB_DIV    => params.clkfb_div,
      CLKOP_DIV    => params.clkop_div,
      CLKOP_ENABLE => "ENABLED",
      CLKOP_CPHASE => params.clkop_div - 1,
      CLKOP_FPHASE => 0,
      FEEDBK_PATH  => "CLKOP",
      OUTDIVIDER_MUXA => "DIVA"
      )
    port map(
      CLKI  => clock_i,
      CLKFB => clkop_s,
      RST   => "not"(reset_n_i),
      CLKOP => clkop_s,
      LOCK  => locked_o
      );

  clock_o <= clkop_s;

end architecture;
