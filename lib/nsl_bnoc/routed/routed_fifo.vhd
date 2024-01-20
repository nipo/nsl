library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory, nsl_bnoc;

entity routed_fifo is
  generic(
    depth_c : natural;
    clock_count_c  : natural range 1 to 2;
    input_slice_c : boolean := false;
    output_slice_c : boolean := false
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic_vector(0 to clock_count_c-1);

    in_i   : in nsl_bnoc.routed.routed_req;
    in_o   : out nsl_bnoc.routed.routed_ack;

    out_o   : out nsl_bnoc.routed.routed_req;
    out_i   : in nsl_bnoc.routed.routed_ack
    );
end entity;

architecture rtl of routed_fifo is

begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth_c,
      data_width_c => 9,
      clock_count_c => clock_count_c,
      output_slice_c => output_slice_c,
      input_slice_c => input_slice_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      out_data_o(8) => out_o.last,
      out_data_o(7 downto 0) => out_o.data,
      out_ready_i => out_i.ready,
      out_valid_o => out_o.valid,
      in_data_i(8) => in_i.last,
      in_data_i(7 downto 0) => in_i.data,
      in_valid_i => in_i.valid,
      in_ready_o => in_o.ready
      );

end architecture;
