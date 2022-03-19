library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity input_delay_fixed is
  generic(
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture xc7 of input_delay_fixed is

  constant ref_freq : real := 200.0e6;
  constant tap_delay_ps_c : integer := integer(1.0e12 / 32 / 2 / ref_freq);
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: unisim.vcomponents.idelaye2
      generic map(
        delay_src => "IDATAIN",
        idelay_type => "FIXED",
        idelay_value => tap_count_i,
        refclk_frequency => ref_freq / 1.0e6
        )
      port map(
        c => '0',
        ce => '0',
        cinvctrl => '0',
        cntvaluein => "00000",
        datain => '0',
        dataout => data_o,
        idatain => data_i,
        inc => '0',
        ld => '0',
        ldpipeen => '0',
        regrst => '0'
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end architecture;
