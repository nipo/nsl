library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep, nsl_bnoc;

entity framed_fifo is
  generic(
    depth : natural;
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

architecture rtl of framed_fifo is

begin

  fifo: hwdep.fifo.fifo_2p
    generic map(
      depth => depth,
      data_width => 9,
      clk_count => clk_count
      )
    port map(
      reset_n_i => p_resetn,
      clk_i => p_clk,
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
