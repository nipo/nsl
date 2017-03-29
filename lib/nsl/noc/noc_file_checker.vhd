library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.testing.all;
use nsl.noc.all;

entity noc_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in noc_cmd;
    p_in_ack   : out noc_rsp
    );
end entity;

architecture rtl of noc_file_checker is

  signal s_fifo : std_ulogic_vector(8 downto 0);
  
begin

  check: nsl.testing.fifo_file_checker
    generic map(
      width => 9,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_full_n => p_in_ack.ack,
      p_write => p_in_val.val,
      p_data => s_fifo
      );
  s_fifo <= p_in_val.more & p_in_val.data;

end architecture;
