library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory;

entity framed_fifo_atomic is
  generic(
    depth : natural;
    txn_depth : natural := 4;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);

    p_in_val   : in nsl_bnoc.framed.framed_req;
    p_in_ack   : out nsl_bnoc.framed.framed_ack;

    p_out_val   : out nsl_bnoc.framed.framed_req;
    p_out_ack   : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of framed_fifo_atomic is

  signal s_in_ack, s_out_ack : nsl_bnoc.framed.framed_ack;
  signal s_out_val, s_in_val : nsl_bnoc.framed.framed_req;
  signal in_end_detected, out_end_detected,
    in_allow, out_allow : std_ulogic;

begin

  frame_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => txn_depth,
      data_width_c => 0,
      clock_count_c => clk_count
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      out_data_o => open,
      out_ready_i => out_end_detected,
      out_valid_o => out_allow,
      in_data_i => (others => '-'),
      in_valid_i => in_end_detected,
      in_ready_o => in_allow
      );
  
  storage: nsl_bnoc.framed.framed_fifo
    generic map(
      depth     => depth,
      clk_count => clk_count
      )
    port map(
      p_resetn => p_resetn,
      p_clk  => p_clk,

      p_in_val => s_in_val,
      p_in_ack => s_in_ack,

      p_out_val => s_out_val,
      p_out_ack => s_out_ack
      );

  in_end_detected <= p_in_val.valid and p_in_val.last and s_in_ack.ready and in_allow;
  out_end_detected <= s_out_val.valid and s_out_val.last and p_out_ack.ready and out_allow;

  p_in_ack.ready <= in_allow and s_in_ack.ready;
  s_in_val.valid <= p_in_val.valid and in_allow;
  s_in_val.data <= p_in_val.data;
  s_in_val.last <= p_in_val.last;
  
  p_out_val.valid <= out_allow and s_out_val.valid;
  p_out_val.data <= s_out_val.data;
  p_out_val.last <= s_out_val.last;
  s_out_ack.ready <= p_out_ack.ready and out_allow;
  

end architecture;
