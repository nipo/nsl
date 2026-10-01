library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_hwconfig, nsl_clocking, nsl_synthesis;
use nsl_memory.fifo.all;

entity fifo_auto is
  generic(
    config_c: fifo_config_t
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic_vector(0 to config_c.clock_count-1);

    out_data_o: out std_ulogic_vector(config_c.data_width-1 downto 0);
    out_ready_i: in std_ulogic;
    out_valid_o: out std_ulogic;
    out_commit_i: in std_ulogic := '1';
    out_rollback_i: in std_ulogic := '0';
    out_available_min_o: out integer range 0 to config_c.word_count;
    out_available_o: out integer range 0 to config_c.word_count+1;

    in_data_i: in std_ulogic_vector(config_c.data_width-1 downto 0);
    in_valid_i: in std_ulogic;
    in_ready_o: out std_ulogic;
    in_commit_i: in std_ulogic := '1';
    in_rollback_i: in std_ulogic := '0';
    in_free_o: out integer range 0 to config_c.word_count
    );
end entity;

-- fifo_shift_register and fifo_lutram have no slices of their own,
-- register slices go around them here. A register slice
-- implementation takes none, its ports are registered already.
-- Handshake pairs only ever pass through port associations, never
-- through signal copies, which would skew both directions of a
-- handshake by a delta cycle each. This takes one instance of the
-- block per combination of slices.
architecture beh of fifo_auto is

  constant implementation_c: fifo_implementation_t
    := fifo_auto_implementation(config_c, nsl_hwconfig.memory_config.lutram);

  subtype data_t is std_ulogic_vector(config_c.data_width-1 downto 0);

  -- Between the input slice and the block.
  signal block_in_data_s: data_t;
  signal block_in_valid_s, block_in_ready_s: std_ulogic;
  -- Between the block and the output slice.
  signal block_out_data_s: data_t;
  signal block_out_valid_s, block_out_ready_s: std_ulogic;

  constant depth_ok_c: boolean := config_c.word_count > 2
    or not (config_c.counters
            or config_c.in_cancellable
            or config_c.out_cancellable);

begin

  assert depth_ok_c
    report "fifo_auto: counters and cancellation need a word_count above 2"
    severity failure;

  depth_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "fifo_auto: counters and cancellation need a word_count above 2",
      condition_c => depth_ok_c
      )
    port map(
      unused_i => '0'
      );

  slice: if implementation_c = FIFO_IMPLEMENTATION_REGISTER_SLICE
  generate
    out_available_min_o <= 0;
    out_available_o <= 0;
    in_free_o <= 0;

    one_clock: if config_c.clock_count = 1
    generate
      impl: nsl_memory.fifo.fifo_register_slice
        generic map(
          data_width_c => config_c.data_width
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          out_data_o => out_data_o,
          out_ready_i => out_ready_i,
          out_valid_o => out_valid_o,

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o
          );
    end generate;

    -- interdomain_fifo_slice only holds one word in flight, the
    -- register slice before it makes up for the second one.
    two_clocks: if config_c.clock_count = 2
    generate
      input: nsl_memory.fifo.fifo_register_slice
        generic map(
          data_width_c => config_c.data_width
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          out_data_o => block_in_data_s,
          out_ready_i => block_in_ready_s,
          out_valid_o => block_in_valid_s,

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o
          );

      crossing: nsl_clocking.interdomain.interdomain_fifo_slice
        generic map(
          data_width_c => config_c.data_width
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i,

          out_data_o => out_data_o,
          out_ready_i => out_ready_i,
          out_valid_o => out_valid_o,

          in_data_i => block_in_data_s,
          in_valid_i => block_in_valid_s,
          in_ready_o => block_in_ready_s
          );
    end generate;
  end generate;

  homogeneous: if implementation_c = FIFO_IMPLEMENTATION_HOMOGENEOUS
  generate
    impl: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => config_c.data_width,
        word_count_c => config_c.word_count,
        clock_count_c => config_c.clock_count,
        input_slice_c => config_c.input_slice,
        output_slice_c => config_c.output_slice,
        register_counters_c => config_c.register_counters,
        in_cancellable_c => config_c.in_cancellable,
        out_cancellable_c => config_c.out_cancellable
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        out_data_o => out_data_o,
        out_ready_i => out_ready_i,
        out_valid_o => out_valid_o,
        out_commit_i => out_commit_i,
        out_rollback_i => out_rollback_i,
        out_available_min_o => out_available_min_o,
        out_available_o => out_available_o,

        in_data_i => in_data_i,
        in_valid_i => in_valid_i,
        in_ready_o => in_ready_o,
        in_commit_i => in_commit_i,
        in_rollback_i => in_rollback_i,
        in_free_o => in_free_o
        );
  end generate;

  single: if implementation_c = FIFO_IMPLEMENTATION_SHIFT_REGISTER
    or implementation_c = FIFO_IMPLEMENTATION_LUTRAM
  generate
    out_available_min_o <= 0;
    out_available_o <= 0;
    in_free_o <= 0;

    input_slice: if config_c.input_slice
    generate
      slice: nsl_memory.fifo.fifo_register_slice
        generic map(
          data_width_c => config_c.data_width
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          out_data_o => block_in_data_s,
          out_ready_i => block_in_ready_s,
          out_valid_o => block_in_valid_s,

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o
          );
    end generate;

    output_slice: if config_c.output_slice
    generate
      slice: nsl_memory.fifo.fifo_register_slice
        generic map(
          data_width_c => config_c.data_width
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          out_data_o => out_data_o,
          out_ready_i => out_ready_i,
          out_valid_o => out_valid_o,

          in_data_i => block_out_data_s,
          in_valid_i => block_out_valid_s,
          in_ready_o => block_out_ready_s
          );
    end generate;

    shift_register_bare: if implementation_c = FIFO_IMPLEMENTATION_SHIFT_REGISTER and not config_c.input_slice and not config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_shift_register
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o,

          out_data_o => out_data_o,
          out_valid_o => out_valid_o,
          out_ready_i => out_ready_i,

          fill_o => open
          );
    end generate;

    shift_register_in: if implementation_c = FIFO_IMPLEMENTATION_SHIFT_REGISTER and config_c.input_slice and not config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_shift_register
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => block_in_data_s,
          in_valid_i => block_in_valid_s,
          in_ready_o => block_in_ready_s,

          out_data_o => out_data_o,
          out_valid_o => out_valid_o,
          out_ready_i => out_ready_i,

          fill_o => open
          );
    end generate;

    shift_register_out: if implementation_c = FIFO_IMPLEMENTATION_SHIFT_REGISTER and not config_c.input_slice and config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_shift_register
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o,

          out_data_o => block_out_data_s,
          out_valid_o => block_out_valid_s,
          out_ready_i => block_out_ready_s,

          fill_o => open
          );
    end generate;

    shift_register_both: if implementation_c = FIFO_IMPLEMENTATION_SHIFT_REGISTER and config_c.input_slice and config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_shift_register
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => block_in_data_s,
          in_valid_i => block_in_valid_s,
          in_ready_o => block_in_ready_s,

          out_data_o => block_out_data_s,
          out_valid_o => block_out_valid_s,
          out_ready_i => block_out_ready_s,

          fill_o => open
          );
    end generate;

    lutram_bare: if implementation_c = FIFO_IMPLEMENTATION_LUTRAM and not config_c.input_slice and not config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_lutram
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o,

          out_data_o => out_data_o,
          out_valid_o => out_valid_o,
          out_ready_i => out_ready_i,

          fill_o => open
          );
    end generate;

    lutram_in: if implementation_c = FIFO_IMPLEMENTATION_LUTRAM and config_c.input_slice and not config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_lutram
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => block_in_data_s,
          in_valid_i => block_in_valid_s,
          in_ready_o => block_in_ready_s,

          out_data_o => out_data_o,
          out_valid_o => out_valid_o,
          out_ready_i => out_ready_i,

          fill_o => open
          );
    end generate;

    lutram_out: if implementation_c = FIFO_IMPLEMENTATION_LUTRAM and not config_c.input_slice and config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_lutram
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => in_data_i,
          in_valid_i => in_valid_i,
          in_ready_o => in_ready_o,

          out_data_o => block_out_data_s,
          out_valid_o => block_out_valid_s,
          out_ready_i => block_out_ready_s,

          fill_o => open
          );
    end generate;

    lutram_both: if implementation_c = FIFO_IMPLEMENTATION_LUTRAM and config_c.input_slice and config_c.output_slice
    generate
      impl: nsl_memory.fifo.fifo_lutram
        generic map(
          data_width_c => config_c.data_width,
          word_count_c => config_c.word_count
          )
        port map(
          reset_n_i => reset_n_i,
          clock_i => clock_i(0),

          in_data_i => block_in_data_s,
          in_valid_i => block_in_valid_s,
          in_ready_o => block_in_ready_s,

          out_data_o => block_out_data_s,
          out_valid_o => block_out_valid_s,
          out_ready_i => block_out_ready_s,

          fill_o => open
          );
    end generate;
  end generate;

end architecture;
