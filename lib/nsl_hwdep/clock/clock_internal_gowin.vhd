 library ieee;
use ieee.std_logic_1164.all;

library nsl_hwdep;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture gowin of clock_internal is

  constant target_freq_c : real := 60.0e6;
  constant osc_freq_c : real := 240.0e6;
  constant divisor_c : integer := (integer(osc_freq_c / target_freq_c) / 2) * 2;
  
  -- 2.1-125 MHz, 5%
  -- freq_div: 2-128, even only
  -- Aim for ~60MHz
  
  component osch
    generic (
      freq_div: integer := 100;
      device: string
    );
    port (
      oscout: out std_logic
    );
  end component;
  
  component osc
    generic (
      freq_div: integer := 100;
      device: string
    );
    port (
      oscout: out std_logic
    );
  end component;

begin

  has_osc: if nsl_hwdep.gowin_config.internal_osc = "osc"
  generate
    inst: osc
      generic map (
        freq_div => divisor_c,
        device => nsl_hwdep.gowin_config.device_name
        )
      port map (
        oscout => clock_o
        );
  end generate;

  has_osch: if nsl_hwdep.gowin_config.internal_osc = "osch"
  generate
    inst: osch
      generic map (
        freq_div => divisor_c,
        device => nsl_hwdep.gowin_config.device_name
        )
      port map (
        oscout => clock_o
        );
  end generate;

end architecture;
