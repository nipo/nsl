 library ieee;
use ieee.std_logic_1164.all;

library nsl_hwdep;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture gw of clock_internal is

  attribute syn_black_box: boolean;
  constant target_freq_c : real := 60.0e6;
  constant osc_freq_c : real := 210.0e6;
  constant divisor_c : integer := (integer(osc_freq_c / target_freq_c) / 2) * 2;
  
  -- 2.1-125 MHz, 5%
  -- freq_div: 2-128, even only
  -- Aim for ~60MHz

begin

  has_osc: if nsl_hwdep.gowin_config.internal_osc = "osc"
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
  begin
    inst: OSC
      generic map (
        FREQ_DIV => divisor_c,
        DEVICE => nsl_hwdep.gowin_config.device_name
        )
      port map (
        OSCOUT => clock_o
        );
  end generate;

  has_osch: if nsl_hwdep.gowin_config.internal_osc = "osch"
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
  begin
    inst: OSCH
      generic map (
        FREQ_DIV => divisor_c
        )
      port map (
        OSCOUT => clock_o
        );
  end generate;

  has_osca: if nsl_hwdep.gowin_config.internal_osc = "osca"
  generate
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

end architecture;
