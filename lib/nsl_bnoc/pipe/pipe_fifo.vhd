library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory;
use nsl_bnoc.pipe.all;

entity pipe_fifo is
  generic(
    word_count_c  : integer;
    clock_count_c : natural range 1 to 2
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i   : in  std_ulogic_vector(0 to clock_count_c-1);

    in_i : in  pipe_req_t;
    in_o : out pipe_ack_t;
    out_o : out pipe_req_t;
    out_i : in pipe_ack_t
    );
end entity;

architecture beh of pipe_fifo is
  
begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => word_count_c,
      data_width_c => 8,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o => out_o.data,
      out_valid_o => out_o.valid,
      out_ready_i => out_i.ready,

      in_data_i => in_i.data,
      in_valid_i => in_i.valid,
      in_ready_o => in_o.ready
      );
  
end architecture;
