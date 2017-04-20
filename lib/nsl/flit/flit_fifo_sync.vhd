library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

entity flit_fifo_sync is
  generic(
    depth : integer
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in flit_cmd;
    p_in_ack   : out flit_ack;

    p_out_val   : out flit_cmd;
    p_out_ack   : in flit_ack
    );
end entity;

architecture rtl of flit_fifo_sync is
begin

  fifo: nsl.fifo.fifo_sync
    generic map(
      depth => depth,
      data_width => 8
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_out_data => p_out_val.data,
      p_out_read => p_out_ack.ack,
      p_out_empty_n => p_out_val.val,
      p_in_data => p_in_val.data,
      p_in_write => p_in_val.val,
      p_in_full_n => p_in_ack.ack
      );
  
end architecture;
