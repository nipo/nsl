library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_memory, nsl_logic;
use work.axi4_mm.all;
use nsl_logic.bool.all;

entity axi4_mm_b_fifo is
  generic(
    config_c : work.axi4_mm.config_t;
    depth_c : positive range 4 to positive'high;
    clock_count_c : integer range 1 to 2 := 1
    );
  port(
    clock_i : in std_ulogic_vector(0 to clock_count_c-1);
    reset_n_i : in std_ulogic;

    in_i : in work.axi4_mm.write_response_t;
    in_o : out work.axi4_mm.handshake_t;

    out_o : out work.axi4_mm.write_response_t;
    out_i : in work.axi4_mm.handshake_t
    );
end entity;

architecture beh of axi4_mm_b_fifo is

  constant data_fifo_width_c: positive := write_response_vector_length(config_c);
  subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);

  signal in_data_s, out_data_s : data_fifo_word_t;
  signal out_data_ready_s, out_data_valid_s : std_ulogic;
  signal in_data_ready_s, in_data_valid_s : std_ulogic;
  
begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth_c,
      data_width_c => in_data_s'length,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o => out_data_s,
      out_ready_i => out_data_ready_s,
      out_valid_o => out_data_valid_s,
      in_data_i => in_data_s,
      in_valid_i => in_data_valid_s,
      in_ready_o => in_data_ready_s
      );

  in_data_s <= vector_pack(config_c, in_i);
  in_data_valid_s <= to_logic(is_valid(config_c, in_i));
  in_o <= accept(config_c, in_data_ready_s = '1');

  out_o <= write_response_vector_unpack(config_c, out_data_s,
                                        valid => out_data_valid_s = '1');
  out_data_ready_s <= out_i.ready;

end architecture;