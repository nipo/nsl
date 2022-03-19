library ieee;
use ieee.std_logic_1164.all;

library unisim;

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

architecture xc7 of output_delay_fixed is

  constant ref_freq : real := 200.0e6;
  constant tap_delay_ps_c : integer := integer(1.0e12 / 32 / 2 / ref_freq);
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: unisim.vcomponents.odelaye2
      generic map(
        delay_src => "ODATAIN",
        odelay_type => "FIXED",
        odelay_value => tap_count_i,
        pipe_sel => "FALSE",
        signal_pattern => "DATA",
        refclk_frequency => ref_freq / 1.0e6
        )
      port map(
        c => '0',
        ce => '0',
        cinvctrl => '0',
        clkin => '0',
        cntvaluein => "00000",
        dataout => data_o,
        inc => '0',
        ld => '0',
        ldpipeen => '0',
        odatain => data_i,
        regrst => '0'
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;

end architecture;
