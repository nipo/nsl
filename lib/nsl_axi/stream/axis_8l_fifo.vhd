library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_axi;
use nsl_axi.stream.all;

entity axis_8l_fifo is
  generic(
    word_count_c : natural;
    clock_count_c  : natural range 1 to 2;
    input_slice_c : boolean := false;
    output_slice_c : boolean := false;
    register_counters_c : boolean := false
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic_vector(0 to clock_count_c-1);

    in_i   : in axis_8l_ms;
    in_o   : out axis_8l_sm;
    free_o : out integer range 0 to word_count_c;

    out_i   : in axis_8l_sm;
    out_o   : out axis_8l_ms;
    available_o : out integer range 0 to word_count_c + 1
    );
end entity;

architecture rtl of axis_8l_fifo is
begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => word_count_c,
      data_width_c => 9,
      clock_count_c => clock_count_c,
      input_slice_c => input_slice_c,
      output_slice_c => output_slice_c,
      register_counters_c => register_counters_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      out_data_o(8) => out_o.tlast,
      out_data_o(7 downto 0) => out_o.tdata,
      out_ready_i => out_i.tready,
      out_valid_o => out_o.tvalid,
      in_data_i(8) => in_i.tlast,
      in_data_i(7 downto 0) => in_i.tdata,
      in_valid_i => in_i.tvalid,
      in_ready_o => in_o.tready,
      out_available_o => available_o,
      in_free_o => free_o
      );

end architecture;
