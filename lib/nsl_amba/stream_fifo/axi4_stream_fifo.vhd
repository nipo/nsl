library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_logic, nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;

entity axi4_stream_fifo is
  generic(
    config_c : config_t;
    depth_c : positive range 4 to positive'high;
    clock_count_c : integer range 1 to 2 := 1
    );
  port(
    clock_i : in std_ulogic_vector(0 to clock_count_c-1);
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;
    in_free_o : out integer range 0 to depth_c;

    out_o : out master_t;
    out_i : in slave_t;
    out_available_o : out integer range 0 to depth_c + 1
    );
end entity;

architecture beh of axi4_stream_fifo is

  constant fifo_elements_c : string := "idskoul";
  constant data_fifo_width_c: positive := vector_length(config_c, fifo_elements_c);
  subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);

  signal in_data_s, out_data_s : data_fifo_word_t;
  signal out_data_ready_s, out_data_valid_s : std_ulogic;
  signal in_data_ready_s, in_data_valid_s : std_ulogic;
  
begin

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => depth_c,
      data_width_c => in_data_s'length,
      clock_count_c => clock_count_c,
      register_counters_c => false
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o => out_data_s,
      out_ready_i => out_data_ready_s,
      out_valid_o => out_data_valid_s,
      in_data_i => in_data_s,
      in_valid_i => in_data_valid_s,
      in_ready_o => in_data_ready_s,
      out_available_o => out_available_o,
      in_free_o => in_free_o
      );

  in_data_s <= vector_pack(config_c, fifo_elements_c, in_i);
  in_data_valid_s <= to_logic(is_valid(config_c, in_i));
  in_o <= accept(config_c, in_data_ready_s = '1');

  out_o <= transfer(config_c,
                    vector_unpack(config_c, fifo_elements_c, out_data_s),
                    force_valid => true, valid => out_data_valid_s = '1');
  out_data_ready_s <= to_logic(is_ready(config_c, out_i));

end architecture;
