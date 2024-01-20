library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_bnoc;

entity framed_fifo is
  generic(
    depth : natural;
    clk_count  : natural range 1 to 2;
    input_slice_c : boolean := false;
    output_slice_c : boolean := false
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

architecture rtl of framed_fifo is

begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth,
      data_width_c => 9,
      clock_count_c => clk_count,
      output_slice_c => output_slice_c,
      input_slice_c => input_slice_c
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      out_data_o(8) => p_out_val.last,
      out_data_o(7 downto 0) => p_out_val.data,
      out_ready_i => p_out_ack.ready,
      out_valid_o => p_out_val.valid,
      in_data_i(8) => p_in_val.last,
      in_data_i(7 downto 0) => p_in_val.data,
      in_valid_i => p_in_val.valid,
      in_ready_o => p_in_ack.ready
      );

end architecture;
