library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.sized.all;

library hwdep;
use hwdep.fifo.all;

entity sized_fifo is
  generic(
    depth : integer;
    clk_count : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);
    
    p_in_val   : in  sized_req;
    p_in_ack   : out sized_ack;

    p_out_val  : out sized_req;
    p_out_ack  : in  sized_ack
    );
end entity;

architecture rtl of sized_fifo is
begin

  fifo: hwdep.fifo.fifo_2p
    generic map(
      depth => depth,
      data_width => 8,
      clk_count => clk_count
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
