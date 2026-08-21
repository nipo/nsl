library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_memory, nsl_simulation;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Four fifo_shift_register instances, each driven by one stimulus process that
-- holds a reference queue. Depths 4 and 10 are the nominal cases, 1
-- and 16 are the ends of the allowed depth range. Every cycle the process drives the
-- handshake at the falling edge, samples the DUT at the rising edge,
-- and checks out_data_o, out_valid_o, in_ready_o and fill_o against
-- the reference. Directed sequences walk the fill boundaries, then
-- randomized handshake patterns keep the FIFO bouncing between empty
-- and full.
entity tb is
end tb;

architecture arch of tb is

  type dut_config_t is
  record
    data_width: natural;
    word_count: natural;
  end record;

  type dut_config_vector is array(natural range <>) of dut_config_t;

  constant dut_config_c: dut_config_vector(0 to 3) := (
    (data_width => 8, word_count => 4),
    (data_width => 16, word_count => 10),
    (data_width => 4, word_count => 1),
    (data_width => 3, word_count => 16)
    );

  constant random_cycle_count_c: natural := 2000;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to dut_config_c'length-1);

begin

  duts: for dut_index in dut_config_c'range
  generate
    constant width_c: natural := dut_config_c(dut_index).data_width;
    constant depth_c: natural := dut_config_c(dut_index).word_count;
    constant name_c: log_context := "fifo_shift_register w" & to_string(width_c)
                                    & " d" & to_string(depth_c);

    subtype word_t is std_ulogic_vector(width_c-1 downto 0);
    type queue_t is array(natural range 0 to depth_c-1) of word_t;

    constant zero_c: word_t := (others => '0');

    signal in_data_s, out_data_s: word_t;
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s: std_ulogic;
    signal fill_s: std_ulogic_vector(0 to depth_c);

    function word(value: integer) return word_t
    is
    begin
      return std_ulogic_vector(to_unsigned(value mod 2**width_c, width_c));
    end function;

  begin

    dut: nsl_memory.fifo.fifo_shift_register
      generic map(
        data_width_c => width_c,
        word_count_c => depth_c
        )
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        in_data_i => in_data_s,
        in_valid_i => in_valid_s,
        in_ready_o => in_ready_s,

        out_data_o => out_data_s,
        out_valid_o => out_valid_s,
        out_ready_i => out_ready_s,

        fill_o => fill_s
        );

    stim: process is
      variable queue_v: queue_t;
      variable count_v: natural;
      variable full_hit_v, empty_hit_v, push_count_v, pop_count_v: natural;
      variable state_v: prbs_state(30 downto 0) := x"c0ffee1" & "011";
      variable bits_v: std_ulogic_vector(0 to width_c+5);
      variable push_v, pop_v: std_ulogic;

      -- Requests one transfer pair, then checks the DUT state that was
      -- visible during that cycle and updates the reference queue with
      -- whatever actually moved.
      procedure step(push_req: in std_ulogic;
                     pop_req: in std_ulogic;
                     wdata: in word_t)
      is
        variable expected_fill_v: std_ulogic_vector(0 to depth_c);
      begin
        wait until falling_edge(clock_s);
        in_valid_s <= push_req;
        in_data_s <= wdata;
        out_ready_s <= pop_req;

        wait until rising_edge(clock_s);

        expected_fill_v := (others => '0');
        expected_fill_v(count_v) := '1';

        assert_equal(name_c, "fill_o", fill_s, expected_fill_v, failure);
        assert_equal(name_c, "out_valid_o",
                     out_valid_s, to_logic(count_v /= 0), failure);
        assert_equal(name_c, "in_ready_o",
                     in_ready_s, to_logic(count_v /= depth_c), failure);

        if pop_req = '1' and out_valid_s = '1' then
          assert_equal(name_c, "out_data_o", out_data_s, queue_v(0), failure);
          for i in 0 to depth_c-2
          loop
            queue_v(i) := queue_v(i+1);
          end loop;
          count_v := count_v - 1;
          pop_count_v := pop_count_v + 1;
        end if;

        if push_req = '1' and in_ready_s = '1' then
          queue_v(count_v) := wdata;
          count_v := count_v + 1;
          push_count_v := push_count_v + 1;
        end if;
      end procedure;

      procedure drain
      is
      begin
        while count_v /= 0
        loop
          step('0', '1', zero_c);
        end loop;
      end procedure;

    begin
      count_v := 0;
      full_hit_v := 0;
      empty_hit_v := 0;
      push_count_v := 0;
      pop_count_v := 0;

      in_valid_s <= '0';
      out_ready_s <= '0';
      in_data_s <= (others => '-');

      wait until reset_n_s = '1';

      step('0', '0', zero_c);

      -- Pop attempt while empty.
      step('0', '1', zero_c);
      step('0', '1', zero_c);

      -- Push into empty, hold, then pop back to empty.
      step('1', '0', word(1));
      step('0', '0', zero_c);
      step('0', '1', zero_c);

      -- Push and pop requested while empty: the push proceeds, the pop
      -- must not, so the FIFO ends up holding one word.
      step('1', '1', word(2));
      assert_equal(name_c, "fill after push+pop on empty", count_v, 1, failure);
      drain;

      -- Fill to full one word at a time.
      for i in 1 to depth_c
      loop
        step('1', '0', word(16+i));
      end loop;
      assert_equal(name_c, "fill after filling up", count_v, depth_c, failure);

      -- Push attempts while full, must be refused without disturbing
      -- the contents.
      step('1', '0', word(200));
      step('1', '0', word(201));

      -- Push and pop requested while full: the pop proceeds, the push
      -- is refused because in_ready_o is registered and low.
      step('1', '1', word(202));
      assert_equal(name_c, "fill after push+pop on full", count_v, depth_c-1, failure);
      drain;

      -- Pop attempt right after reaching empty.
      step('0', '1', zero_c);

      -- Simultaneous push and pop at every intermediate fill level.
      for level in 1 to depth_c-1
      loop
        for i in 1 to level
        loop
          step('1', '0', word(16*level+i));
        end loop;
        assert_equal(name_c, "fill before push+pop", count_v, level, failure);
        step('1', '1', word(16*level+15));
        assert_equal(name_c, "fill after push+pop", count_v, level, failure);
        drain;
      end loop;

      -- Back-to-back push and pop at full rate from empty.
      for i in 1 to 4*depth_c
      loop
        step('1', '1', word(i));
      end loop;
      drain;

      -- Randomized handshake patterns. Each phase uses a different
      -- duty cycle on the two strobes so that the FIFO spends time
      -- backed up against full and starved at empty.
      for phase in 0 to 3
      loop
        for cycle in 0 to random_cycle_count_c-1
        loop
          bits_v := prbs_bit_string(state_v, prbs31, bits_v'length);
          state_v := prbs_forward(state_v, prbs31, bits_v'length);

          case phase is
            when 0 =>
              push_v := bits_v(0) or bits_v(1);
              pop_v := bits_v(2) and bits_v(3);
            when 1 =>
              push_v := bits_v(0) and bits_v(1);
              pop_v := bits_v(2) or bits_v(3);
            when 2 =>
              push_v := bits_v(0);
              pop_v := bits_v(2);
            when others =>
              push_v := bits_v(0) or (bits_v(1) and bits_v(4));
              pop_v := bits_v(2) or (bits_v(3) and bits_v(5));
          end case;

          if count_v = depth_c then
            full_hit_v := full_hit_v + 1;
          end if;
          if count_v = 0 then
            empty_hit_v := empty_hit_v + 1;
          end if;

          step(push_v, pop_v, bits_v(6 to bits_v'right));
        end loop;
      end loop;

      drain;

      wait until falling_edge(clock_s);
      in_valid_s <= '0';
      out_ready_s <= '0';
      in_data_s <= (others => '-');

      assert_equal(name_c, "cycles spent full is too low",
                   full_hit_v > 100, true, failure);
      assert_equal(name_c, "cycles spent empty is too low",
                   empty_hit_v > 100, true, failure);
      assert_equal(name_c, "transferred word count is too low",
                   push_count_v > 1500, true, failure);
      assert_equal(name_c, "pushed and popped word counts differ",
                   push_count_v, pop_count_v, failure);

      log_info(name_c, "done, " & to_string(push_count_v) & " words through, "
               & to_string(full_hit_v) & " cycles full, "
               & to_string(empty_hit_v) & " cycles empty");

      done_s(dut_index) <= '1';

      wait;
    end process;

  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
