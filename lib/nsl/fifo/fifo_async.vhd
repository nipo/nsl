library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
use hwdep.fifo.all;

entity fifo_async is
  generic(
    data_width : integer;
    depth      : integer
    );
  port(
    p_resetn   : in  std_ulogic;

    p_out_clk     : in  std_ulogic;
    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_ready    : in  std_ulogic;
    p_out_valid : out std_ulogic;

    p_in_clk    : in  std_ulogic;
    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_valid  : in  std_ulogic;
    p_in_ready : out std_ulogic
    );
end fifo_async;

architecture rtl of fifo_async is

begin

  impl: hwdep.fifo.fifo_2p
    generic map(
      data_width => data_width,
      depth => depth,
      clk_count => 2
      )
    port map(
      reset_n_i => p_resetn,

      clk_i(0) => p_in_clk,
      clk_i(1) => p_out_clk,
      out_data_o => p_out_data,
      out_ready_i => p_out_ready,
      out_valid_o => p_out_valid,

      in_data_i => p_in_data,
      in_valid_i => p_in_valid,
      in_ready_o => p_in_ready
      );
    
end rtl;
