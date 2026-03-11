library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_memory, nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;

entity axi4_stream_fifo_cancellable is
  generic(
    config_c : config_t;
    word_count_l2_c : integer;
    out_pkt_available_range_c: integer range 0 to integer'high := 0
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    out_o : out master_t;
    out_i : in  slave_t;
    out_commit_i : in std_ulogic := '1';
    out_rollback_i : in std_ulogic := '0';
    out_available_o : out unsigned(word_count_l2_c downto 0);
    out_pkt_available_o : out integer range 0 to out_pkt_available_range_c;

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
  constant pkt_available_range_l2 : integer := nsl_math.arith.log2(out_pkt_available_range_c+1);
  signal pkt_counter : unsigned(pkt_available_range_l2-1 downto 0);


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

  packet_counter_proc: process(clock_i, reset_n_i) is
    variable out_v : master_t;
    variable inc, dec: boolean;
  begin
    if reset_n_i = '0' then 
      pkt_counter <= (others => '0');
    elsif rising_edge(clock_i) then
      out_v := vector_unpack(config_c, fifo_elements_c, out_data_s);
      inc := is_valid(config_c, in_i) and is_last(config_c, in_i);
      dec := out_data_valid_s = '1' and is_last(config_c, out_v) and is_ready(config_c, out_i);
      if inc and not dec then
        pkt_counter <= pkt_counter + 1;
      elsif dec and not inc then 
        pkt_counter <= pkt_counter - 1;
      end if;
    end if;
  end process;

  out_pkt_available_o <= to_integer(pkt_counter);
  out_data_ready_s <= out_i.ready;
  
end architecture;
