library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_transceiver.lane.all;
use nsl_simulation.logging.all;

-- A fabric pattern generator feeding a fabric pattern checker, with
-- a way to corrupt what passes between them.
--
-- The checker is not told where the pattern starts, only which one
-- it is: it has to find the phase from the bits themselves, which is
-- what lets it work behind a deserialiser that framed the line
-- wherever it liked.
entity prbs_bench is
  generic(
    byte_count_c : natural;
    mode_c : prbs_mode_t;
    -- A pattern the checker is switched to part way, which it must
    -- fail to find.
    other_mode_c : prbs_mode_t;
    label_c : string
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of prbs_bench is

  signal gen_data_s, rx_data_s : byte_string(0 to byte_count_c-1);
  signal gen_valid_s : std_ulogic;

  signal mode_s : prbs_mode_t;
  signal force_error_s : std_ulogic;
  signal restart_s : std_ulogic;
  signal corrupt_s : std_ulogic;
  -- The word sink's backpressure, driven low to hold the line, and
  -- the word it takes: the sink reads exactly when the generator
  -- parts with a word.
  signal ready_s : std_ulogic;
  signal taken_s : std_ulogic;

  signal locked_s, error_s : std_ulogic;
  signal error_bit_count_s : integer range 0 to byte_count_c*8;

begin

  generator: nsl_transceiver.prbs.prbs_generator
    generic map(
      byte_count_c => byte_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      mode_i => mode_c,
      force_error_i => force_error_s,
      ready_i => ready_s,

      data_o => gen_data_s,
      valid_o => gen_valid_s
      );

  -- The line. One bit of one byte goes wrong on request, which is
  -- what a bit error on a pair looks like to the checker.
  corrupt: process(gen_data_s, corrupt_s) is
  begin
    rx_data_s <= gen_data_s;

    if corrupt_s = '1' then
      rx_data_s(0)(0) <= not gen_data_s(0)(0);
    end if;
  end process;

  taken_s <= gen_valid_s and ready_s;

  checker: nsl_transceiver.prbs.prbs_checker
    generic map(
      byte_count_c => byte_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      mode_i => mode_s,
      restart_i => restart_s,

      data_i => rx_data_s,
      valid_i => taken_s,

      locked_o => locked_s,
      error_o => error_s,
      error_bit_count_o => error_bit_count_s
      );

  sequencer: process
    constant ctxt : log_context := label_c;
    variable cycles_v : natural;
    variable errors_v : natural;
    variable bits_v : natural;

    -- Waits for the checker to report the pattern found, or says how
    -- long it had been looking.
    procedure wait_locked(budget : natural; what : string) is
      variable waited_v : natural;
    begin
      waited_v := 0;
      while locked_s /= '1' loop
        wait until rising_edge(clock_i);
        waited_v := waited_v + 1;
        assert waited_v < budget
          report what & ": the checker has been hunting for "
          & integer'image(waited_v) & " words"
          severity failure;
      end loop;

      log_info(ctxt, what & " took " & integer'image(waited_v) & " words");
    end procedure;

    -- Lets the line run clean and insists nothing is reported.
    procedure run_clean(word_count : natural; what : string) is
    begin
      for i in 0 to word_count-1 loop
        wait until rising_edge(clock_i);

        assert error_s = '0'
          report what & ": the checker reported "
          & integer'image(error_bit_count_s)
          & " wrong bits in a word nothing had touched"
          severity failure;
        assert locked_s = '1'
          report what & ": the checker lost a pattern nothing had"
          & " interrupted"
          severity failure;
      end loop;
    end procedure;

    -- Holds the line, then lets it go. The pattern has to pick up
    -- where it stopped: a generator running on through a stall would
    -- leave a hole in the sequence and the far end would have to
    -- hunt for its phase again.
    procedure stall(word_count : natural; what : string) is
    begin
      wait until falling_edge(clock_i);
      ready_s <= '0';

      for i in 0 to word_count-1 loop
        wait until rising_edge(clock_i);
      end loop;

      wait until falling_edge(clock_i);
      ready_s <= '1';

      for i in 0 to 15 loop
        wait until rising_edge(clock_i);
        assert error_s = '0'
          report what & ": the checker reported "
          & integer'image(error_bit_count_s)
          & " wrong bits once the line started again"
          severity failure;
        assert locked_s = '1'
          report what & ": the checker lost the pattern over a stall"
          severity failure;
      end loop;

      log_info(ctxt, what & " left the pattern where it was");
    end procedure;

    -- Breaks exactly one bit and counts what comes back.
    procedure one_bit(on_the_line : boolean; what : string) is
    begin
      errors_v := 0;
      bits_v := 0;

      wait until falling_edge(clock_i);
      if on_the_line then
        corrupt_s <= '1';
      else
        force_error_s <= '1';
      end if;

      wait until falling_edge(clock_i);
      corrupt_s <= '0';
      force_error_s <= '0';

      -- Long enough for the wrong bit to have been seen and for the
      -- deepest tap to have read it back out again, had the checker
      -- been feeding itself the line instead of its own predictions.
      for i in 0 to 63 loop
        wait until rising_edge(clock_i);
        if error_s = '1' then
          errors_v := errors_v + 1;
          bits_v := bits_v + error_bit_count_s;
        end if;
      end loop;

      assert errors_v = 1
        report what & ": " & integer'image(errors_v)
        & " words came back wrong from a single wrong bit"
        severity failure;

      assert bits_v = 1
        report what & ": " & integer'image(bits_v)
        & " bits came back wrong from a single wrong bit"
        severity failure;

      assert locked_s = '1'
        report what & ": the checker lost the pattern over one bit"
        severity failure;

      log_info(ctxt, what & " was counted once and nothing else");
    end procedure;
  begin
    done_o <= '0';
    mode_s <= mode_c;
    force_error_s <= '0';
    restart_s <= '0';
    corrupt_s <= '0';
    ready_s <= '1';

    wait until reset_n_i = '1';

    wait_locked(256, "finding the pattern");
    run_clean(64, "running clean");

    stall(5, "a stalled word sink");

    one_bit(true, "a wrong bit on the line");
    run_clean(64, "running clean after a line error");

    one_bit(false, "a wrong bit the generator was asked for");
    run_clean(64, "running clean after a forced error");

    -- Told to expect a different pattern, the checker has to give
    -- up: a pattern it finds anyway would mean it is not really
    -- predicting one.
    wait until falling_edge(clock_i);
    mode_s <= other_mode_c;

    cycles_v := 0;
    while locked_s /= '0' loop
      wait until rising_edge(clock_i);
      cycles_v := cycles_v + 1;
      assert cycles_v < 256
        report "the checker kept reporting a pattern it was no longer"
        & " looking for"
        severity failure;
    end loop;

    log_info(ctxt, "gave up on the wrong pattern in "
             & integer'image(cycles_v) & " words");

    for i in 0 to 255 loop
      wait until rising_edge(clock_i);
      assert locked_s = '0'
        report "the checker found "
        & prbs_mode_t'image(other_mode_c) & " in a line carrying "
        & prbs_mode_t'image(mode_c)
        severity failure;
    end loop;

    -- And has to come back when told the right one again.
    wait until falling_edge(clock_i);
    mode_s <= mode_c;
    restart_s <= '1';
    wait until falling_edge(clock_i);
    restart_s <= '0';

    wait_locked(256, "finding the pattern again");
    run_clean(64, "running clean again");

    done_o <= '1';
    wait;
  end process;

end architecture;
