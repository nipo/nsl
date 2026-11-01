library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_simulation, nsl_data;
use nsl_data.text.all;
use nsl_transceiver.lane.all;
use nsl_simulation.logging.all;

-- A fabric pattern generator feeding a plain IO serialiser, and a
-- plain IO deserialiser feeding a fabric pattern checker, over a
-- cable whose length is swept across a whole received word.
--
-- The two ends deserialise at different widths on purpose. Nothing
-- about a test pattern is word shaped: it is a bit stream, and a
-- checker that finds its phase in the bits themselves has no reason
-- to care how many of them arrive at a time or where the receiver
-- framed them. A link that only passes when both widths match would
-- mean the checker is relying on framing it is not entitled to.
--
-- What the two ends do have to agree on is which bit of a word goes
-- on the line first, because a word handed over reversed is not a
-- phase of the pattern but a different sequence altogether. That is
-- what agree_c is for: set false, the bench insists the pattern is
-- never found, which is what makes a pass with it true mean
-- something.
entity serdes_bench is
  generic(
    -- Bits the serialiser takes per word, and bits the deserialiser
    -- gives back per word. Deliberately unrelated.
    tx_ratio_c : positive;
    rx_ratio_c : positive;
    mode_c : prbs_mode_t;
    agree_c : boolean := true;
    -- Cable lengths tried, from zero in steps of step_c.
    step_count_c : natural;
    step_c : time;
    -- Words the pattern has to come back clean for at each length.
    clean_word_count_c : natural := 64;
    label_c : string
    );
  port(
    -- One bit period, and one word period per end.
    bit_clock_i : in std_ulogic;
    tx_clock_i : in std_ulogic;
    rx_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of serdes_bench is

  -- Hunting costs the checker the pattern's own order in bits before
  -- it has even seen enough history to predict anything, then the
  -- clean words it wants in a row. Generous, so that a length that
  -- fails fails for a reason.
  constant lock_budget_c : natural := 1024;

  signal tx_bits_s : std_ulogic_vector(0 to tx_ratio_c-1);
  signal rx_bits_s : std_ulogic_vector(0 to rx_ratio_c-1);
  signal tx_valid_s : std_ulogic;

  signal serial_s, cable_s : std_ulogic;

  -- Cable length under test. A signal rather than a generic, so one
  -- instance walks the whole sweep. Initialised, because the cable
  -- exists before the sweep process has run and a time left at its
  -- default is negative.
  signal delay_s : time := 0 ps;

  signal restart_s : std_ulogic;
  signal locked_s, error_s : std_ulogic;

begin

  generator: nsl_transceiver.prbs.prbs_generator
    generic map(
      bit_count_c => tx_ratio_c
      )
    port map(
      clock_i => tx_clock_i,
      reset_n_i => reset_n_i,

      mode_i => mode_c,
      force_error_i => '0',
      -- The serialiser takes a word every word period.
      ready_i => '1',

      data_o => tx_bits_s,
      valid_o => tx_valid_s
      );

  -- First bit of the word on the line first, which is the order the
  -- generator hands them over in.
  serializer: nsl_io.serdes.serdes_output
    generic map(
      left_first_c => true,
      ddr_mode_c => false,
      to_delay_c => false,
      ratio_c => tx_ratio_c
      )
    port map(
      serial_clock_i => bit_clock_i,
      parallel_clock_i => tx_clock_i,
      reset_n_i => reset_n_i,

      parallel_i => tx_bits_s,
      serial_o => serial_s
      );

  -- The cable. Transport delay, because a wire carries a pulse
  -- however short it is.
  cable_s <= transport serial_s after delay_s;

  deserializer: nsl_io.serdes.serdes_input
    generic map(
      left_first_c => agree_c,
      ddr_mode_c => false,
      from_delay_c => false,
      ratio_c => rx_ratio_c
      )
    port map(
      serial_clock_i => bit_clock_i,
      parallel_clock_i => rx_clock_i,
      reset_n_i => reset_n_i,

      serial_i => cable_s,
      parallel_o => rx_bits_s,
      -- Nothing to slip to: a pattern has no framing to find.
      bitslip_i => '0',
      mark_o => open
      );

  checker: nsl_transceiver.prbs.prbs_checker
    generic map(
      bit_count_c => rx_ratio_c
      )
    port map(
      clock_i => rx_clock_i,
      reset_n_i => reset_n_i,

      mode_i => mode_c,
      restart_i => restart_s,

      data_i => rx_bits_s,
      -- A word arrives every word period, there being no elastic
      -- buffer between the two ends.
      valid_i => '1',

      locked_o => locked_s,
      error_o => error_s,
      error_bit_count_o => open
      );

  sweep: process
    constant ctxt : log_context := label_c;
    variable cycles_v : natural;
    variable worst_v : natural;
  begin
    done_o <= '0';
    restart_s <= '0';
    delay_s <= 0 ps;

    wait until reset_n_i = '1';

    worst_v := 0;

    for step in 0 to step_count_c-1 loop
      delay_s <= step * step_c;

      -- Make the checker forget the phase it had settled on, so each
      -- length is found from scratch rather than inherited from the
      -- length before it.
      restart_s <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(rx_clock_i);
      end loop;
      restart_s <= '0';

      if agree_c then
        cycles_v := 0;
        while locked_s /= '1' loop
          wait until rising_edge(rx_clock_i);
          cycles_v := cycles_v + 1;
          assert cycles_v < lock_budget_c
            report "a cable of " & to_string(step * step_c)
            & ": the checker has been hunting for "
            & integer'image(cycles_v) & " words"
            severity failure;
        end loop;

        if cycles_v > worst_v then
          worst_v := cycles_v;
        end if;

        for i in 0 to clean_word_count_c-1 loop
          wait until rising_edge(rx_clock_i);
          assert error_s = '0'
            report "a cable of " & to_string(step * step_c)
            & ": the checker found the pattern and then lost a word of it"
            severity failure;
          assert locked_s = '1'
            report "a cable of " & to_string(step * step_c)
            & ": the checker gave the pattern up on a clean line"
            severity failure;
        end loop;
      else
        for i in 0 to lock_budget_c-1 loop
          wait until rising_edge(rx_clock_i);
          assert locked_s = '0'
            report "a cable of " & to_string(step * step_c)
            & ": the checker found a pattern in a line read the"
            & " wrong way round"
            severity failure;
        end loop;
      end if;
    end loop;

    if agree_c then
      log_info(ctxt, "carried the pattern at all "
               & integer'image(step_count_c) & " cable lengths from 0 to "
               & to_string((step_count_c - 1) * step_c)
               & ", found in at most " & integer'image(worst_v) & " words");
    else
      log_info(ctxt, "never found the pattern, the two ends disagreeing"
               & " on which bit goes first");
    end if;

    done_o <= '1';
    wait;
  end process;

end architecture;
