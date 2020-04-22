library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory;
use nsl_memory.fifo.all;

entity fifo_sync is
  generic(
    data_width : integer;
    depth      : integer
    );
  port(
    p_resetn : in  std_ulogic;
    p_clk    : in  std_ulogic;

    p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_out_ready    : in  std_ulogic;
    p_out_valid : out std_ulogic;

    p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
    p_in_valid  : in  std_ulogic;
    p_in_ready : out std_ulogic
    );
end fifo_sync;

architecture rtl of fifo_sync is
begin

  impl: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => data_width,
      word_count_c => depth,
      clock_count_c => 1
      )
    port map(
      reset_n_i => p_resetn,
      clock_i(0) => p_clk,

      out_data_o => p_out_data,
      out_ready_i => p_out_ready,
      out_valid_o => p_out_valid,

      in_data_i => p_in_data,
      in_valid_i => p_in_valid,
      in_ready_o => p_in_ready
      );
  
end rtl;
