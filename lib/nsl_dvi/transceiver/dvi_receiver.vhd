library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_clocking, nsl_line_coding, nsl_video, work;
use nsl_video.mode.all;

entity dvi_receiver is
  generic(
    mode_c : nsl_video.mode.mode_t;
    -- A lane is judged over this many symbols at a time, and has to
    -- show at least this many control symbols among them.  The window
    -- has to outlast a line, so that every window holds some
    -- blanking.
    window_l2_c : natural := 12;
    control_min_c : natural := 256;
    -- Control symbols also have to turn up in a run this long.  Four
    -- of the 1024 ten-bit words are control symbols, so a lane cut
    -- anywhere at all throws single ones up by chance often enough to
    -- satisfy any count -- but never two in a row, let alone sixteen.
    -- Blanking is hundreds of symbols long, so a lane cut in the right
    -- place shows runs of hundreds.
    control_run_min_c : natural := 16
    );
  port(
    reset_n_i : in std_ulogic;

    -- The link's own clock and its three lanes, as the pads hand them
    -- over.  The differential receiver is in the pad, so what arrives
    -- here is already one signal per pair.
    clock_i : in std_ulogic;
    data_i : in std_ulogic_vector(0 to 2);

    -- Hold this to make every lane look for its symbol boundary
    -- again.  Nothing about the link is disturbed: the clock it
    -- recovers keeps running and the source is never told anything, so
    -- it has no reason to start over.
    realign_i : in std_ulogic := '0';

    -- The clock everything downstream of here runs on, which is the
    -- link's, and whether the PLL made it.
    pixel_clock_o : out std_ulogic;
    -- Five times the above, which is what a transmitter needs to
    -- serialise with.  A sink forwarding what it receives wants both
    -- from here rather than from a PLL of its own: made together, they
    -- keep step, and the link it sends runs at exactly the rate of the
    -- one it took in.
    serial_clock_o : out std_ulogic;
    locked_o : out std_ulogic;

    -- Whether each lane found where its symbols start, and whether it
    -- is still seeing them.
    aligned_o : out std_ulogic_vector(0 to 2);
    control_o : out std_ulogic_vector(0 to 2);

    tmds_o : out work.dvi.symbol_vector_t
    );
end entity;

architecture beh of dvi_receiver is

  use nsl_clocking.pll.all;

  -- Ten bits per pixel per channel, sent on both edges, so the bit
  -- clock is five times the pixel clock.  Both come from the one PLL
  -- so they keep a known phase to each other.
  constant pll_config_c : pll_config_t := pll_config(
    input_hz => pixel_clock_hz(mode_c),
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count-1);
  signal bit_clock_s, word_clock_s : std_ulogic;
  signal pll_locked_s : std_ulogic;
  signal word_reset_n_s : std_ulogic;

  signal delayed_s : std_ulogic_vector(0 to 2);
  type parallel_vector is array (natural range <>) of std_ulogic_vector(0 to 9);
  signal parallel_s : parallel_vector(0 to 2);

  -- The run of control symbols a lane is in, and the longest it
  -- managed over the window.
  subtype run_count_t is unsigned(9 downto 0);
  type run_count_vector is array (natural range <>) of run_count_t;
  signal control_run_s, control_best_s : run_count_vector(0 to 2);

  signal delay_shift_s, delay_mark_s : std_ulogic_vector(0 to 2);
  signal serdes_shift_s, serdes_mark_s : std_ulogic_vector(0 to 2);
  signal valid_s, ready_s : std_ulogic_vector(0 to 2);

  -- How many control symbols a lane showed over a window, and what
  -- the window before it concluded.
  --
  -- Presence is not enough to judge a lane by.  Four of the 1024
  -- ten-bit words are control symbols, so a lane sampled anywhere at
  -- all throws one up about every 256 symbols by chance, which is
  -- often enough to keep any "seen one recently" test satisfied
  -- forever.  A lane that is genuinely aligned spends a quarter of
  -- its time in blanking and shows thousands.  What tells the two
  -- apart is how many, not whether.
  subtype window_count_t is unsigned(window_l2_c downto 0);
  type count_vector is array (natural range <>) of window_count_t;
  signal control_count_s : count_vector(0 to 2);
  signal window_s : unsigned(window_l2_c-1 downto 0);
  signal dense_s : std_ulogic_vector(0 to 2);

begin

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_i,
      clock_o => pll_clock_s,
      reset_n_i => reset_n_i,
      locked_o => pll_locked_s
      );

  bit_clock_s <= pll_clock_s(0);
  word_clock_s <= pll_clock_s(1);

  -- Nothing below here runs until there is a clock for it to run on,
  -- and it all starts over when asked to look again.  Asking is
  -- asynchronous -- a button, most likely -- and lands in the word
  -- clock the same way the lock does.
  word_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => word_clock_s,
      data_i => pll_locked_s and not realign_i,
      data_o => word_reset_n_s
      );

  -- One window for all three lanes, they being on the one clock
  window: process(word_clock_s, word_reset_n_s) is
  begin
    if rising_edge(word_clock_s) then
      window_s <= window_s + 1;
    end if;

    if word_reset_n_s = '0' then
      window_s <= (others => '0');
    end if;
  end process;

  lanes: for i in 0 to 2
  generate
    -- Where in the eye the bit is sampled
    delay: nsl_io.delay.input_delay_variable
      port map(
        clock_i => word_clock_s,
        reset_n_i => word_reset_n_s,
        mark_o => delay_mark_s(i),
        shift_i => delay_shift_s(i),

        data_i => data_i(i),
        data_o => delayed_s(i)
        );

    des: nsl_io.serdes.serdes_ddr10_input
      generic map(
        left_to_right_c => false
        )
      port map(
        bit_clock_i => bit_clock_s,
        word_clock_i => word_clock_s,
        reset_n_i => word_reset_n_s,

        serial_i => delayed_s(i),
        parallel_o => parallel_s(i),

        bitslip_i => serdes_shift_s(i),
        mark_o => serdes_mark_s(i)
        );

    -- What a lane shows over a window, and what that says about it
    watch: process(word_clock_s, word_reset_n_s) is
      variable decoded: std_ulogic_vector(5 downto 0);
      variable counted: window_count_t;
      variable run, best: run_count_t;
      variable is_control: boolean;
    begin
      if rising_edge(word_clock_s) then
        decoded := nsl_line_coding.tmds.control_decode(
          nsl_line_coding.tmds.tmds_symbol_t(parallel_s(i)));

        -- A basic control symbol, which is what blanking is made of.
        -- TERC4 words say valid too, and a data island is made of
        -- those, so they are not counted here.
        is_control := decoded(5) = '1' and decoded(4) = '0';

        if is_control then
          counted := control_count_s(i) + 1;
        else
          counted := control_count_s(i);
        end if;

        -- How long the run this symbol belongs to has become, held at
        -- the top rather than wrapping round to nothing
        if not is_control then
          run := (others => '0');
        elsif control_run_s(i) = run_count_t'(others => '1') then
          run := control_run_s(i);
        else
          run := control_run_s(i) + 1;
        end if;

        if run > control_best_s(i) then
          best := run;
        else
          best := control_best_s(i);
        end if;

        if window_s = 0 then
          -- Enough of them, and some of them together.  Either alone
          -- can be had by chance; both cannot.
          if counted >= control_min_c and best >= control_run_min_c then
            dense_s(i) <= '1';
          else
            dense_s(i) <= '0';
          end if;

          counted := (others => '0');
          best := (others => '0');
        end if;

        control_count_s(i) <= counted;
        control_run_s(i) <= run;
        control_best_s(i) <= best;
      end if;

      if word_reset_n_s = '0' then
        control_run_s(i) <= (others => '0');
        control_best_s(i) <= (others => '0');
        control_count_s(i) <= (others => '0');
        dense_s(i) <= '0';
      end if;
    end process;

    valid_s(i) <= dense_s(i);

    aligner: nsl_io.delay.input_delay_aligner
      generic map(
        -- A delay step has to be given several windows to show what it
        -- is worth, and a couple more to settle first.
        stabilization_cycle_c => 2 * 2**window_l2_c,
        stabilization_delay_c => 4 * 2**window_l2_c
        )
      port map(
        clock_i => word_clock_s,
        reset_n_i => word_reset_n_s,

        delay_shift_o => delay_shift_s(i),
        delay_mark_i => delay_mark_s(i),
        serdes_shift_o => serdes_shift_s(i),
        serdes_mark_i => serdes_mark_s(i),

        -- A lane that stops looking right is trained again.  Training
        -- once and never looking back leaves a lane that settled
        -- somewhere marginal sitting there: it passed when it was
        -- asked, the link drifted, and nothing ever asks again.  What
        -- it decodes is then wrong for as long as the link is up, and
        -- whether a link comes up usable becomes a matter of luck.
        --
        -- Restarting is only heard while training is done, so a lane
        -- being trained is left alone until it has an answer to judge.
        restart_i => (ready_s(i) and not dense_s(i)) or realign_i,

        valid_i => valid_s(i),
        ready_o => ready_s(i)
        );

    tmds_o(i) <= nsl_line_coding.tmds.tmds_symbol_t(parallel_s(i));
  end generate;

  pixel_clock_o <= word_clock_s;
  serial_clock_o <= bit_clock_s;
  locked_o <= pll_locked_s;
  aligned_o <= ready_s;
  control_o <= dense_s;

end architecture;
