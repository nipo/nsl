library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_hwconfig, nsl_memory, nsl_simulation;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_hwconfig.memory_config.all;
use nsl_memory.fifo.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- fifo_auto regression.
--
-- The selection rules are checked on their own against LUT RAM facts
-- of several kinds of targets.
--
-- Then one fifo_auto instance per implementation path: each DUT
-- declares the implementation it expects the simulation target to
-- select, which is checked, and a producer/consumer pair pushes a
-- numbered sequence through it with random handshakes, checking the
-- words come out in order. Two-clock instances run their consumer on
-- a clock of another period.
entity tb is
end tb;

architecture arch of tb is

  type dut_t is
  record
    config: fifo_config_t;
    expected: fifo_implementation_t;
  end record;

  type dut_vector is array(natural range <>) of dut_t;

  constant dut_c: dut_vector := (
    (fifo_config(data_width => 8, word_count => 1),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 32, word_count => 2),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 2, word_count => 8),
     FIFO_IMPLEMENTATION_SHIFT_REGISTER),
    (fifo_config(data_width => 8, word_count => 2, output_slice => true),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 8, word_count => 3),
     FIFO_IMPLEMENTATION_LUTRAM),
    (fifo_config(data_width => 16, word_count => 16),
     FIFO_IMPLEMENTATION_LUTRAM),
    (fifo_config(data_width => 8, word_count => 5,
                 input_slice => true, output_slice => true),
     FIFO_IMPLEMENTATION_LUTRAM),
    (fifo_config(data_width => 8, word_count => 17, input_slice => true),
     FIFO_IMPLEMENTATION_LUTRAM),
    (fifo_config(data_width => 4, word_count => 64, output_slice => true),
     FIFO_IMPLEMENTATION_LUTRAM),
    (fifo_config(data_width => 8, word_count => 128),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 4, counters => true),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 8, in_cancellable => true),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 16, clock_count => 2),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 2, clock_count => 2,
                 input_slice => true, output_slice => true),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 8, word_count => 1, clock_count => 2),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 16, word_count => 2, clock_count => 2),
     FIFO_IMPLEMENTATION_REGISTER_SLICE),
    (fifo_config(data_width => 8, word_count => 4, clock_count => 2,
                 output_slice => true),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 3, clock_count => 2),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 5, clock_count => 2,
                 counters => true),
     FIFO_IMPLEMENTATION_HOMOGENEOUS),
    (fifo_config(data_width => 8, word_count => 13, clock_count => 2,
                 counters => true, register_counters => true),
     FIFO_IMPLEMENTATION_HOMOGENEOUS)
    );

  constant word_count_c: natural := 1000;
  constant watchdog_c: time := 200 us;

  signal clock_s: std_ulogic_vector(0 to 1);
  signal reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2*dut_c'length);

  procedure check_rules
  is
    constant ctx: log_context := "rules";

    constant gowin_c: lutram_t := (present => true, async_read => true,
                                   depth => 16, width => 4,
                                   fifo_depth_max => 64);
    constant xilinx_c: lutram_t := (present => true, async_read => true,
                                    depth => 32, width => 6,
                                    fifo_depth_max => 128);
    constant none_c: lutram_t := (present => false, async_read => false,
                                  depth => 0, width => 0,
                                  fifo_depth_max => 0);
    constant sync_read_c: lutram_t := (present => true, async_read => false,
                                       depth => 16, width => 4,
                                       fifo_depth_max => 64);

    procedure expect(what: string;
                     config: fifo_config_t;
                     lutram: lutram_t;
                     expected: fifo_implementation_t)
    is
      constant got: fifo_implementation_t := fifo_auto_implementation(config, lutram);
    begin
      assert_equal(ctx, what,
                   fifo_implementation_t'image(got),
                   fifo_implementation_t'image(expected),
                   failure);
    end procedure;
  begin
    -- Register slices for up to two words, whatever the width and
    -- the clock count, as long as no counters nor cancellation are
    -- asked for.
    expect("d1 w64", fifo_config(64, 1), gowin_c, FIFO_IMPLEMENTATION_REGISTER_SLICE);
    expect("d2 w32", fifo_config(32, 2), gowin_c, FIFO_IMPLEMENTATION_REGISTER_SLICE);
    expect("d2 slices", fifo_config(32, 2, input_slice => true, output_slice => true),
           gowin_c, FIFO_IMPLEMENTATION_REGISTER_SLICE);
    expect("d1 2 clocks", fifo_config(8, 1, clock_count => 2), gowin_c,
           FIFO_IMPLEMENTATION_REGISTER_SLICE);
    expect("d2 2 clocks", fifo_config(8, 2, clock_count => 2), gowin_c,
           FIFO_IMPLEMENTATION_REGISTER_SLICE);
    expect("none d2 w32", fifo_config(32, 2), none_c, FIFO_IMPLEMENTATION_REGISTER_SLICE);

    -- Features only fifo_homogeneous has, even when tiny.
    expect("2 clocks", fifo_config(8, 3, clock_count => 2), gowin_c,
           FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("counters", fifo_config(8, 3, counters => true), gowin_c,
           FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("in cancel", fifo_config(8, 16, in_cancellable => true), gowin_c,
           FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("out cancel", fifo_config(8, 16, out_cancellable => true), gowin_c,
           FIFO_IMPLEMENTATION_HOMOGENEOUS);

    -- Shift register for few bits.
    expect("d16 w1", fifo_config(1, 16), gowin_c, FIFO_IMPLEMENTATION_SHIFT_REGISTER);
    expect("d4 w4", fifo_config(4, 4), gowin_c, FIFO_IMPLEMENTATION_SHIFT_REGISTER);
    expect("d4 w5", fifo_config(5, 4), gowin_c, FIFO_IMPLEMENTATION_LUTRAM);
    expect("d3 w8", fifo_config(8, 3), gowin_c, FIFO_IMPLEMENTATION_LUTRAM);
    expect("d17 w0", fifo_config(0, 17), gowin_c, FIFO_IMPLEMENTATION_LUTRAM);

    -- LUT RAM up to the target's limit, block RAM beyond.
    expect("gowin d64", fifo_config(32, 64), gowin_c, FIFO_IMPLEMENTATION_LUTRAM);
    expect("gowin d65", fifo_config(32, 65), gowin_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("xilinx d128", fifo_config(32, 128), xilinx_c, FIFO_IMPLEMENTATION_LUTRAM);
    expect("xilinx d129", fifo_config(32, 129), xilinx_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("sync read d16", fifo_config(32, 16), sync_read_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);

    -- No LUT RAM: registers for few bits, block RAM otherwise.
    expect("none d8 w8", fifo_config(8, 8), none_c, FIFO_IMPLEMENTATION_SHIFT_REGISTER);
    expect("none d16 w4", fifo_config(4, 16), none_c, FIFO_IMPLEMENTATION_SHIFT_REGISTER);
    expect("none d8 w9", fifo_config(9, 8), none_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("none d17 w1", fifo_config(1, 17), none_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);
    expect("none d3 w32", fifo_config(32, 3), none_c, FIFO_IMPLEMENTATION_HOMOGENEOUS);

    log_info(ctx, "done");
  end procedure;

begin

  rules: process is
  begin
    done_s(2*dut_c'length) <= '0';
    check_rules;
    done_s(2*dut_c'length) <= '1';
    wait;
  end process;

  duts: for dut_index in dut_c'range
  generate
    constant config_c: fifo_config_t := dut_c(dut_index).config;
    constant width_c: natural := config_c.data_width;
    constant in_clock_c: natural := 0;
    constant out_clock_c: natural := config_c.clock_count-1;
    constant name_c: log_context := "fifo_auto #" & to_string(dut_index)
                                    & " w" & to_string(width_c)
                                    & " d" & to_string(config_c.word_count);
    constant implementation_c: fifo_implementation_t
      := fifo_auto_implementation(config_c, nsl_hwconfig.memory_config.lutram);

    subtype word_t is std_ulogic_vector(width_c-1 downto 0);

    signal in_data_s, out_data_s: word_t;
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s: std_ulogic;
    signal in_free_s: integer range 0 to config_c.word_count;

    function word(value: integer) return word_t
    is
    begin
      return std_ulogic_vector(resize(to_unsigned(value, 31), width_c));
    end function;

  begin

    assert implementation_c = dut_c(dut_index).expected
      report name_c & ": selects " & fifo_implementation_t'image(implementation_c)
      & ", expected " & fifo_implementation_t'image(dut_c(dut_index).expected)
      severity failure;

    one_clock: if config_c.clock_count = 1
    generate
      dut: nsl_memory.fifo.fifo_auto
        generic map(
          config_c => config_c
          )
        port map(
          reset_n_i => reset_n_s,
          clock_i(0) => clock_s(0),

          out_data_o => out_data_s,
          out_ready_i => out_ready_s,
          out_valid_o => out_valid_s,

          in_data_i => in_data_s,
          in_valid_i => in_valid_s,
          in_ready_o => in_ready_s,
          in_free_o => in_free_s
          );
    end generate;

    two_clocks: if config_c.clock_count = 2
    generate
      dut: nsl_memory.fifo.fifo_auto
        generic map(
          config_c => config_c
          )
        port map(
          reset_n_i => reset_n_s,
          clock_i(0) => clock_s(0),
          clock_i(1) => clock_s(1),

          out_data_o => out_data_s,
          out_ready_i => out_ready_s,
          out_valid_o => out_valid_s,

          in_data_i => in_data_s,
          in_valid_i => in_valid_s,
          in_ready_o => in_ready_s,
          in_free_o => in_free_s
          );
    end generate;

    producer: process is
      variable state_v: prbs_state(30 downto 0) := x"1234567" & "101";
      variable bits_v: std_ulogic_vector(0 to 1);
      variable sent_v: natural := 0;
      variable offered_v: boolean := false;
      variable refused_v: natural := 0;
    begin
      done_s(2*dut_index) <= '0';
      in_valid_s <= '0';
      in_data_s <= (others => '-');
      state_v := prbs_forward(state_v, prbs31, 7 * dut_index + 1);

      wait until reset_n_s = '1';

      while sent_v < word_count_c
      loop
        wait until rising_edge(clock_s(in_clock_c));
        if offered_v and in_ready_s = '1' then
          sent_v := sent_v + 1;
        elsif offered_v then
          refused_v := refused_v + 1;
        end if;

        -- A registered count lags the handshake by a cycle.
        if config_c.counters and not config_c.register_counters then
          if in_ready_s = '1' then
            assert_equal(name_c, "in_free_o while ready",
                         in_free_s /= 0, true, failure);
          end if;
        end if;

        wait until falling_edge(clock_s(in_clock_c));
        bits_v := prbs_bit_string(state_v, prbs31, bits_v'length);
        state_v := prbs_forward(state_v, prbs31, bits_v'length);

        -- Mostly pushing in the first half so that the fifo fills up,
        -- less than popping in the second half so that it drains.
        if sent_v < word_count_c / 2 then
          offered_v := (bits_v(0) or bits_v(1)) = '1';
        else
          offered_v := (bits_v(0) and bits_v(1)) = '1';
        end if;
        offered_v := offered_v and sent_v < word_count_c;

        if offered_v then
          in_valid_s <= '1';
          in_data_s <= word(sent_v);
        else
          in_valid_s <= '0';
          in_data_s <= (others => '-');
        end if;
      end loop;

      in_valid_s <= '0';
      in_data_s <= (others => '-');

      assert_equal(name_c, "input never backed up", refused_v > 0, true, failure);

      done_s(2*dut_index) <= '1';
      wait;
    end process;

    consumer: process is
      variable state_v: prbs_state(30 downto 0) := x"7654321" & "011";
      variable bits_v: std_ulogic_vector(0 to 1);
      variable received_v: natural := 0;
    begin
      done_s(2*dut_index+1) <= '0';
      out_ready_s <= '0';
      state_v := prbs_forward(state_v, prbs31, 11 * dut_index + 3);

      wait until reset_n_s = '1';

      while received_v < word_count_c
      loop
        wait until rising_edge(clock_s(out_clock_c));
        if out_ready_s = '1' and out_valid_s = '1' then
          assert_equal(name_c, "out_data_o #" & to_string(received_v),
                       out_data_s, word(received_v), failure);
          received_v := received_v + 1;
        end if;

        wait until falling_edge(clock_s(out_clock_c));
        bits_v := prbs_bit_string(state_v, prbs31, bits_v'length);
        state_v := prbs_forward(state_v, prbs31, bits_v'length);
        if received_v < word_count_c / 2 then
          out_ready_s <= bits_v(0) and bits_v(1);
        else
          out_ready_s <= bits_v(0) or bits_v(1);
        end if;
      end loop;

      out_ready_s <= '0';

      -- Nothing more may come out.
      for i in 0 to 15
      loop
        wait until rising_edge(clock_s(out_clock_c));
        assert_equal(name_c, "out_valid_o after the last word",
                     out_valid_s, '0', failure);
      end loop;

      log_info(name_c, fifo_implementation_t'image(implementation_c)
               & ", " & to_string(received_v) & " words through");

      done_s(2*dut_index+1) <= '1';
      wait;
    end process;

  end generate;

  watchdog: process is
  begin
    wait for watchdog_c;
    assert false
      report "Watchdog expired"
      severity failure;
    wait;
  end process;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 17 ns,
      reset_duration => (others => 32 ns),
      clock_o => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
