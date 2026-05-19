library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_logic, nsl_avalon;
use nsl_avalon.avalon_st.all;
use nsl_logic.bool.all;

entity avalon_st_fifo is
  generic(
    config_c      : config_t;
    depth_c       : positive range 4 to positive'high;
    clock_count_c : integer  range 1 to 2 := 1
    );
  port(
    clock_i   : in std_ulogic_vector(0 to clock_count_c-1);
    reset_n_i : in std_ulogic;

    in_i      : in  source_t;
    in_o      : out sink_t;
    in_free_o : out integer range 0 to depth_c;

    out_o           : out source_t;
    out_i           : in  sink_t;
    out_available_o : out integer range 0 to depth_c + 1
    );
end entity;

architecture beh of avalon_st_fifo is

  -- Everything but `valid` rides in the FIFO word; `valid` is the
  -- FIFO's own valid signal.
  constant fifo_elements_c   : string   := "dceusmpq";
  constant data_fifo_width_c : positive := vector_length(config_c, fifo_elements_c);
  subtype data_fifo_word_t is std_ulogic_vector(0 to data_fifo_width_c-1);

  signal in_data_s,  out_data_s         : data_fifo_word_t;
  signal in_data_valid_s, in_data_ready_s : std_ulogic;
  signal out_data_valid_s, out_data_ready_s : std_ulogic;

begin

  assert config_c.ready_latency = 0
    report "avalon_st_fifo requires config_c.ready_latency = 0"
    severity failure;
  assert config_c.ready_allowance = 0
    report "avalon_st_fifo requires config_c.ready_allowance = 0"
    severity failure;

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c        => depth_c,
      data_width_c        => in_data_s'length,
      clock_count_c       => clock_count_c,
      register_counters_c => false
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      out_data_o      => out_data_s,
      out_ready_i    => out_data_ready_s,
      out_valid_o    => out_data_valid_s,
      out_available_o => out_available_o,

      in_data_i  => in_data_s,
      in_valid_i => in_data_valid_s,
      in_ready_o => in_data_ready_s,
      in_free_o  => in_free_o
      );

  in_data_s       <= vector_pack(config_c, fifo_elements_c, in_i);
  in_data_valid_s <= to_logic(is_valid(config_c, in_i));
  in_o            <= accept(config_c, in_data_ready_s = '1');

  out_o <= transfer(config_c,
                    vector_unpack(config_c, fifo_elements_c, out_data_s),
                    force_valid => true, valid => out_data_valid_s = '1');
  out_data_ready_s <= to_logic(is_ready(config_c, out_i));

end architecture;
