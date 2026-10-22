 library ieee;
use ieee.std_logic_1164.all;

library nsl_hwconfig;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture gw of clock_internal is

  attribute syn_black_box: boolean;
  constant target_freq_c : real := 60.0e6;

begin

  has_osc: if nsl_hwconfig.gowin_config.internal_osc = "osc"
  generate
    component OSC is
      generic (
        FREQ_DIV : integer := 100;
        DEVICE : string := "GW1N-4"
        );
      port (
        OSCOUT: out std_logic
        );
    end component;
    attribute syn_black_box of OSC : component is true;

    constant osc_freq_c : real := 210.0e6;
    constant divisor_c : integer := (integer(osc_freq_c / target_freq_c) / 2) * 2;
  begin
    inst: OSC
      generic map (
        FREQ_DIV => divisor_c,
        DEVICE => nsl_hwconfig.gowin_config.device_name
        )
      port map (
        OSCOUT => clock_o
        );
  end generate;

  has_osch: if nsl_hwconfig.gowin_config.internal_osc = "osch"
  generate
    component OSCH is
      generic (
        FREQ_DIV : integer := 96
        );
      port (
        OSCOUT: out std_logic
        );
    end component;
    attribute syn_black_box of OSCH : component is true;

    constant osc_freq_c : real := 210.0e6;
    constant divisor_c : integer := (integer(osc_freq_c / target_freq_c) / 2) * 2;
  begin
    inst: OSCH
      generic map (
        FREQ_DIV => divisor_c
        )
      port map (
        OSCOUT => clock_o
        );
  end generate;

  has_osca: if nsl_hwconfig.gowin_config.internal_osc = "osca"
  generate
    constant osc_freq_c : real := 210.0e6;
    constant divisor_c : integer := (integer(osc_freq_c / target_freq_c) / 2) * 2;

    component OSCA is
      generic (
        FREQ_DIV : integer := 96
        );
      port (
        OSCOUT: out std_logic;
        OSCEN: in std_logic
        );
    end component;
    attribute syn_black_box of OSCA : component is true;
  begin
    inst: OSCA
      generic map (
        FREQ_DIV => divisor_c
        )
      port map (
        OSCOUT => clock_o,
        OSCEN => '1'
        );
  end generate;

  has_oscz: if nsl_hwconfig.gowin_config.internal_osc = "oscz"
  generate
    component OSCZ is
      generic (
        FREQ_DIV : integer := 100;
        S_RATE : string := "FAST"
        );
      port (
        OSCEN : in std_logic;
        OSCOUT: out std_logic
        );
    end component;
    attribute syn_black_box of OSCZ : component is true;
  begin
    inst: OSCZ
      generic map (
        FREQ_DIV => 2
        )
      port map (
        OSCEN => '1',
        OSCOUT => clock_o
        );
  end generate;

end architecture;
