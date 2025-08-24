library ieee;
use ieee.std_logic_1164.all;

library nsl_io, gowin;
use nsl_io.diff.all;

entity pad_diff_output is
  generic(
    is_clock : boolean := false
    );
  port(
    p_se : in std_ulogic;
    p_diff : out diff_pair
    );
end entity;

architecture gw1n of pad_diff_output is

  attribute syn_black_box: boolean ;

  component TLVDS_OBUF is
    PORT(
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic
      );
  end component;
  attribute syn_black_box of TLVDS_OBUF : component is true;

begin

  se2diff: TLVDS_OBUF
    port map(
      o => p_diff.p,
      ob => p_diff.n,
      i => p_se
      );
  
end architecture;
