library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_memory, nsl_amba;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;

entity axi4_stream_fifo_cancellable is
  generic(
    config_c : config_t;
    word_count_l2_c : integer
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    out_o : out master_t;
    out_i : in  slave_t;
    out_commit_i : in std_ulogic := '1';
    out_rollback_i : in std_ulogic := '0';
    out_available_o : out unsigned(word_count_l2_c downto 0);

    in_i  : in  master_t;
    in_o : out slave_t;
    in_commit_i : in std_ulogic := '1';
    in_rollback_i : in std_ulogic := '0';
    in_free_o : out unsigned(word_count_l2_c downto 0)
    );
end entity;

architecture beh of axi4_stream_fifo_cancellable is

  constant fifo_elements_c : string := "idskoul";
  constant data_fifo_width_c: positive := vector_length(config_c, fifo_elements_c);
  subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);

  signal in_data_s, out_data_s : data_fifo_word_t;
  signal out_data_ready_s, out_data_valid_s : std_ulogic;
  signal in_data_ready_s, in_data_valid_s : std_ulogic;

begin

  impl : nsl_memory.fifo.fifo_cancellable
    generic map(
      data_width_c    => data_fifo_width_c,
      word_count_l2_c => word_count_l2_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      out_data_o      => out_data_s,
      out_ready_i     => out_data_ready_s,
      out_valid_o     => out_data_valid_s,
      out_commit_i    => out_commit_i,
      out_rollback_i  => out_rollback_i,
      out_available_o => out_available_o,

      in_data_i     => in_data_s,
      in_valid_i    => in_data_valid_s,
      in_ready_o    => in_data_ready_s,
      in_commit_i   => in_commit_i,
      in_rollback_i => in_rollback_i,
      in_free_o     => in_free_o
      );
  
  in_data_s <= vector_pack(config_c, fifo_elements_c, in_i);
  in_data_valid_s <= to_logic(is_valid(config_c, in_i));
  in_o <= accept(config_c, in_data_ready_s = '1');

  unpack: process(out_data_s, out_data_valid_s) is
  begin
    out_o <= vector_unpack(config_c, fifo_elements_c, out_data_s);
    out_o.valid <= out_data_valid_s;
  end process;
  out_data_ready_s <= out_i.ready;
  
end architecture;
