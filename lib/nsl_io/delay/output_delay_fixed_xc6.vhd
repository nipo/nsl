library ieee;
use ieee.std_logic_1164.all;

library unisim;
library nsl_data, nsl_hwdep;
use nsl_data.text.if_else;

entity output_delay_fixed is
  generic(
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture xc6 of output_delay_fixed is

  constant tap_delay_ps_c : integer := nsl_hwdep.xc6_config.iodelay2_tap_ps;
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;
  constant data_rate: string := if_else(is_ddr_c, "DDR", "SDR");

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: unisim.vcomponents.iodelay2
      generic map(
        data_rate => data_rate,
        delay_src => "ODATAIN",
        idelay_type => "FIXED",
        idelay_value => tap_count_i,
        idelay2_value => tap_count_i,
        odelay_value => tap_count_i,
        serdes_mode => "NONE",
        sim_tapdelay_value => tap_delay_ps_c
        )
      port map(
        cal => '0',
        ce => '0',
        clk => '0',
        odatain => data_i,
        idatain => '0',
        inc => '0',
        ioclk0 => '0',
        ioclk1 => '0',
        dout => data_o,
        rst => '0',
        t => '0'
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;

end architecture;
