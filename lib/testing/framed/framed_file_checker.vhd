library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;

library testing;
use testing.fifo.all;

entity framed_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl.framed.framed_req;
    p_in_ack   : out nsl.framed.framed_ack;

    p_done     : out std_ulogic
    );
end entity;

architecture rtl of framed_file_checker is

  signal s_fifo : std_ulogic_vector(8 downto 0);
  
begin

  check: testing.fifo.fifo_file_checker
    generic map(
      width => 9,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_ready => p_in_ack.ack,
      p_valid => p_in_val.val,
      p_data => s_fifo,
      p_done => p_done
      );
  s_fifo <= p_in_val.more & p_in_val.data;

end architecture;
