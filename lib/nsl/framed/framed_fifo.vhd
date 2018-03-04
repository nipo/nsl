library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
use hwdep.fifo.all;

library nsl;
use nsl.framed.all;

entity framed_fifo is
  generic(
    depth : natural;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);

    p_in_val   : in nsl.framed.framed_req;
    p_in_ack   : out nsl.framed.framed_ack;

    p_out_val   : out nsl.framed.framed_req;
    p_out_ack   : in nsl.framed.framed_ack
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
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_out_data(8) => p_out_val.last,
      p_out_data(7 downto 0) => p_out_val.data,
      p_out_ready => p_out_ack.ready,
      p_out_valid => p_out_val.valid,
      p_in_data(8) => p_in_val.last,
      p_in_data(7 downto 0) => p_in_val.data,
      p_in_valid => p_in_val.valid,
      p_in_ready => p_in_ack.ready
      );

end architecture;
