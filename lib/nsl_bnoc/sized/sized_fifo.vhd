library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory;

entity sized_fifo is
  generic(
    depth : integer;
    clk_count : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);
    
    p_in_val   : in  nsl_bnoc.sized.sized_req;
    p_in_ack   : out nsl_bnoc.sized.sized_ack;

    p_out_val  : out nsl_bnoc.sized.sized_req;
    p_out_ack  : in  nsl_bnoc.sized.sized_ack
    );
end entity;

architecture rtl of sized_fifo is
begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth,
      data_width_c => 8,
      clock_count_c => clk_count
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,

      out_data_o => p_out_val.data,
      out_ready_i => p_out_ack.ready,
      out_valid_o => p_out_val.valid,

      in_data_i => p_in_val.data,
      in_valid_i => p_in_val.valid,
      in_ready_o => p_in_ack.ready
      );
  
end architecture;
