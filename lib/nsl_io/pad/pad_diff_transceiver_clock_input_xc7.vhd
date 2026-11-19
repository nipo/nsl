library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_transceiver_clock_input is
  port(
    p_diff : in diff_pair;
    p_se : out std_ulogic
    );
end entity;

architecture rtl of pad_diff_transceiver_clock_input is

  attribute BOX_TYPE : string;

  component IBUFDS_GTE2
    port (
      O : out std_ulogic;
      ODIV2 : out std_ulogic;
      CEB : in std_ulogic;
      I : in std_ulogic;
      IB : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IBUFDS_GTE2 : component is "PRIMITIVE";

begin

  buf: IBUFDS_GTE2
    port map(
      I => p_diff.p,
      IB => p_diff.n,
      CEB => '0',
      O => p_se,
      ODIV2 => open
      );

end architecture;
