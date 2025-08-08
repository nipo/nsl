library ieee;
use ieee.std_logic_1164.all;

library nsl_hwdep;

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

  constant tap_count_i : integer := integer(real(delay_ps_c) / nsl_hwdep.gowin_config.iodelay_step_ps);

  component iodelay
      generic (
          c_static_dly:integer:=0;
          dyn_dly_en:string:="false";
          adapt_en:string:="false"
      );
      port(
          do:out std_logic;
          df:out std_logic;
          di:in std_logic;
          sdtap:in std_logic;
          value:in std_logic;
          dlystep:in std_logic_vector(7 downto 0)
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
        dlystep => (others => '0'),
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
