library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_hwconfig;
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

  attribute BOX_TYPE : string;

  component IODELAY2
    generic (
      COUNTER_WRAPAROUND : string := "WRAPAROUND";
      DATA_RATE : string := "SDR";
      DELAY_SRC : string := "IO";
      IDELAY2_VALUE : integer := 0;
      IDELAY_MODE : string := "NORMAL";
      IDELAY_TYPE : string := "DEFAULT";
      IDELAY_VALUE : integer := 0;
      ODELAY_VALUE : integer := 0;
      SERDES_MODE : string := "NONE";
      SIM_TAPDELAY_VALUE : integer := 75
      );
    port (
      BUSY : out std_ulogic;
      DATAOUT : out std_ulogic;
      DATAOUT2 : out std_ulogic;
      DOUT : out std_ulogic;
      TOUT : out std_ulogic;
      CAL : in std_ulogic;
      CE : in std_ulogic;
      CLK : in std_ulogic;
      IDATAIN : in std_ulogic;
      INC : in std_ulogic;
      IOCLK0 : in std_ulogic;
      IOCLK1 : in std_ulogic;
      ODATAIN : in std_ulogic;
      RST : in std_ulogic;
      T : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IODELAY2 : component is "PRIMITIVE";

  constant tap_delay_ps_c : integer := nsl_hwconfig.xc6_config.iodelay2_tap_ps;
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;
  constant data_rate: string := if_else(is_ddr_c, "DDR", "SDR");

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: iodelay2
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
