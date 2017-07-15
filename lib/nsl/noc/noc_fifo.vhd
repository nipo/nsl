library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.noc.all;

entity noc_fifo is
  generic(
    depth : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in noc_cmd;
    p_in_ack   : out noc_rsp;

    p_out_val   : out noc_cmd;
    p_out_ack   : in noc_rsp
    );
end entity;

architecture rtl of noc_fifo is

  signal s_in_data, s_out_data : std_ulogic_vector(8 downto 0);

begin

  fifo: nsl.fifo.sync_fifo
    generic map(
      depth => depth,
      data_width => 9
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_out_data => s_out_data,
      p_out_read => p_out_ack.ack,
      p_out_empty_n => p_out_val.val,
      p_in_data => s_in_data,
      p_in_write => p_in_val.val,
      p_in_full_n => p_in_ack.ack
      );

  s_in_data <= p_in_val.more & p_in_val.data;
  p_out_val.more <= s_out_data(8);
  p_out_val.data <= s_out_data(7 downto 0);
  
end architecture;
