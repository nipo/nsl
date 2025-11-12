library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


library nsl_memory, nsl_logic, nsl_amba, nsl_data, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.endian.all;

entity axi4_stream_fifo is
  generic(
    config_c : config_t;
    depth_c : positive range 4 to positive'high;
    out_pkt_available_range_c: integer range 0 to integer'high;
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
    out_pkt_available : out integer range 0 to out_pkt_available_range_c;
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

  generate_fifo_homogenous: if clock_i'length /= 1 generate
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
    end generate;

  generate_fifo_cancellable: if clock_i'length = 1 generate
      constant depth_l2_c : integer := nsl_math.arith.log2(depth_c);
      -- +1 for the case out_pkt_available_range_c = 1
      constant pkt_available_range_l2 : integer := nsl_math.arith.log2(out_pkt_available_range_c+1);
      signal out_available : unsigned(depth_l2_c downto 0);
      signal in_free : unsigned(depth_l2_c downto 0);
      signal pkt_counter : unsigned(pkt_available_range_l2-1 downto 0);
    begin
    fifo: nsl_memory.fifo.fifo_cancellable
     generic map(
        data_width_c => in_data_s'length,
        word_count_l2_c => depth_l2_c
    )
     port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i(0),
        out_data_o => out_data_s,
        out_ready_i => out_data_ready_s,
        out_valid_o => out_data_valid_s,
        out_available_o => out_available,
        in_data_i => in_data_s,
        in_valid_i => in_data_valid_s,
        in_ready_o => in_data_ready_s,
        in_free_o => in_free
    );
    out_available_o <= to_integer(out_available);
    in_free_o <= to_integer(in_free);

    packet_counter_proc: process(reset_n_i, clock_i) is
      variable out_v : master_t;
      variable inc, dec: boolean;
    begin
      if rising_edge(clock_i(0)) then
        out_v := vector_unpack(config_c, fifo_elements_c, out_data_s);
        inc := is_valid(config_c, in_i) and is_last(config_c, in_i);
        dec := out_data_valid_s = '1' and is_last(config_c, out_v) and is_ready(config_c, out_i);
        if inc and not dec then
          pkt_counter <= pkt_counter + 1;
        elsif dec and not inc then 
          pkt_counter <= pkt_counter - 1;
        end if;
      end if;

      if reset_n_i = '0' then
        pkt_counter <= (others => '0');
      end if;
    end process;
    out_pkt_available <= to_integer(pkt_counter);
  end generate; 

  in_data_s <= vector_pack(config_c, fifo_elements_c, in_i);
  in_data_valid_s <= to_logic(is_valid(config_c, in_i));
  in_o <= accept(config_c, in_data_ready_s = '1');

  out_o <= transfer(config_c,
                    vector_unpack(config_c, fifo_elements_c, out_data_s),
                    force_valid => true, valid => out_data_valid_s = '1');
  out_data_ready_s <= to_logic(is_ready(config_c, out_i));

end architecture;
