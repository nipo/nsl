library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library testing;
use testing.fifo.all;

library nsl;
use nsl.framed.all;

entity framed_file_reader is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_out_val   : out nsl.framed.framed_req;
    p_out_ack   : in nsl.framed.framed_ack;

    p_done : out std_ulogic
    );
end entity;

architecture rtl of framed_file_reader is

  signal s_fifo : std_ulogic_vector(8 downto 0);
  
begin

  gen: testing.fifo.fifo_file_reader
    generic map(
      width => 9,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_valid => p_out_val.val,
      p_ready => p_out_ack.ack,
      p_data => s_fifo,
      p_done => p_done
      );
  p_out_val.more <= s_fifo(8);
  p_out_val.data <= s_fifo(7 downto 0);

end architecture;
