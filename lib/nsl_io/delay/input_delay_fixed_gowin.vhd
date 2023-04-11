library ieee;
use ieee.std_logic_1164.all;

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

architecture gowin of input_delay_fixed is

  constant tap_delay_ps_c : integer := 30;
  constant tap_count_i : integer := delay_ps_c / tap_delay_ps_c;

  component IODELAY is
    GENERIC (  C_STATIC_DLY : integer := 0);
    PORT (
      DI : IN std_logic;
      SDTAP : IN std_logic;
      SETN : IN std_logic;
      VALUE : IN std_logic;
      DO : OUT std_logic;
      DF : OUT std_logic
      );
  end component;

begin

  has_delay: if delay_ps_c /= 0
  generate
    inst: iodelay
      generic map(
        c_static_dly => tap_count_i
        )
      port map(
        di => data_i,
        sdtap => '0',
        setn => '0',
        value => '0',
        df => open,
        do => data_o
        );
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end architecture;
