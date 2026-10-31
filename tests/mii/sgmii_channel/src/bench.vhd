library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_io, nsl_line_coding, nsl_simulation, nsl_data;
use nsl_data.text.all;
use nsl_simulation.logging.all;

-- Two SGMII serdes backends across a cable whose length is swept
-- over a whole word period, one delay step at a time.
--
-- The backend recovers the stream with a variable delay line and a
-- bit slip, both driven by an alignment loop that scores the delay
-- it is sitting on. Which delay and which slip it has to find is
-- decided by the cable, and nothing in the design makes one length
-- harder than another: a length the loop cannot converge on is a
-- defect in the loop. Sweeping the whole word period is the only way
-- to find one, because a board gives you a single length and it is
-- usually one that happens to work.
--
-- The score fed to the loop is the comma. It has to be something
-- only a correctly framed stream produces: a stream read at the
-- right instant but on the wrong word boundary still decodes to
-- valid code groups most of the time, so code validity alone lets
-- the loop settle on a boundary that never yields a symbol the
-- protocol wants. The comma's bit pattern occurs nowhere else in a
-- code stream, which is what makes it the one usable answer, and it
-- is why the SGMII driver scores on whether the symbol was expected
-- rather than merely legal.
entity channel_bench is
  generic(
    -- Cable lengths tried, from zero in steps of step_c. A word is
    -- ten bits, so a sweep spanning ten bit periods visits every bit
    -- slip as well as every phase within a bit.
    step_count_c : natural;
    step_c : time;
    -- Frames checked at each length before moving on.
    frame_count_c : natural := 4;
    label_c : string
    );
  port(
    clock125_i : in std_ulogic;
    clock625_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of channel_bench is

  -- One comma opens each frame and the rest counts, so a frame that
  -- arrived slipped by a bit, or short a symbol, is visible without
  -- knowing the cable's length. Kept short so a comma falls inside
  -- every window the alignment loop scores a tap over.
  constant frame_symbol_count_c : natural := 4;
  constant comma_c : nsl_line_coding.ibm_8b10b.data_t
    := nsl_line_coding.ibm_8b10b.K28_5;

  -- How long a stream is credited with being framed after its last
  -- comma. Longer than a frame, shorter than the loop's patience.
  constant comma_age_max_c : natural := 12;

  -- The return path is not under test, so it is short and fixed.
  constant return_delay_c : time := 1 ns;

  -- The loop sweeps a 64 tap line and slips at most once per pass,
  -- so a length needing every slip costs ten passes. Measured worst
  -- case over this sweep is about 10400 words.
  constant converge_budget_c : natural := 16384;

  signal near_m2p_s, far_m2p_s : nsl_mii.sgmii.sgmii_m2p_t;
  signal near_p2m_s, far_p2m_s : nsl_mii.sgmii.sgmii_p2m_t;

  signal near_out_s, far_out_s : nsl_io.diff.diff_pair;
  signal near_in_s, far_in_s : nsl_io.diff.diff_pair;

  signal cable_s, cable_delayed_s : std_ulogic;

  -- Cable length under test. A signal rather than a generic, so one
  -- instance walks the whole sweep. Initialised, because the cable
  -- exists before the sweep process has run and a time left at its
  -- default is negative.
  signal delay_s : time := 0 ps;

  -- Held high to make both ends start their search over.
  signal restart_s : std_ulogic;

  signal tx_symbol_s : nsl_line_coding.ibm_8b10b.data_t;
  signal near_framed_s, far_framed_s : std_ulogic;

begin

  -- The stream both ends send and the far end has to recover.
  feed: process
    variable index_v : natural;
  begin
    tx_symbol_s <= comma_c;
    index_v := 1;

    loop
      wait until falling_edge(clock125_i);

      if index_v = 0 then
        tx_symbol_s <= comma_c;
      else
        tx_symbol_s <= nsl_line_coding.ibm_8b10b.data(
          std_ulogic_vector(to_unsigned(index_v, 8)));
      end if;

      index_v := (index_v + 1) mod frame_symbol_count_c;
    end loop;
  end process;

  near_m2p_s.symbol <= tx_symbol_s;
  near_m2p_s.tx_disparity <= '0';
  -- The far end sends the reference stream too rather than echoing
  -- what it recovered, so the near end's own alignment does not
  -- depend on the length under test.
  far_m2p_s.symbol <= tx_symbol_s;
  far_m2p_s.tx_disparity <= '0';

  -- Whether a comma has arrived recently enough for the stream to
  -- count as framed.
  watchers: for e in 0 to 1 generate

    signal p2m_s : nsl_mii.sgmii.sgmii_p2m_t;
    signal framed_s : std_ulogic;

  begin

    p2m_s <= near_p2m_s when e = 0 else far_p2m_s;

    watch: process(clock125_i, reset_n_i) is
      variable age_v : natural range 0 to comma_age_max_c;
    begin
      if rising_edge(clock125_i) then
        if p2m_s.code_err = '0' and p2m_s.symbol.control = '1'
          and p2m_s.symbol.data = comma_c.data then
          age_v := 0;
        elsif age_v /= comma_age_max_c then
          age_v := age_v + 1;
        end if;

        if age_v = comma_age_max_c then
          framed_s <= '0';
        else
          framed_s <= '1';
        end if;
      end if;

      if reset_n_i = '0' then
        age_v := comma_age_max_c;
        framed_s <= '0';
      end if;
    end process;

    near_gen: if e = 0 generate
      near_framed_s <= framed_s;
    end generate;

    far_gen: if e = 1 generate
      far_framed_s <= framed_s;
    end generate;

  end generate;

  near_m2p_s.valid_symbol <= near_framed_s and not near_p2m_s.code_err;
  far_m2p_s.valid_symbol <= far_framed_s and not far_p2m_s.code_err;

  -- The rule the SGMII driver uses: an end that believes it is
  -- aligned and does not like what it receives asks for another
  -- search.
  near_m2p_s.align_rst <= restart_s
                          or (near_p2m_s.align_ready
                              and not near_m2p_s.valid_symbol);
  far_m2p_s.align_rst <= restart_s
                         or (far_p2m_s.align_ready
                             and not far_m2p_s.valid_symbol);

  -- The cable. Transport delay, because a pair carries a pulse
  -- however short it is.
  cable_s <= nsl_io.diff.to_se(near_out_s);
  cable_delayed_s <= transport cable_s after delay_s;
  far_in_s <= nsl_io.diff.to_diff(cable_delayed_s);

  near_in_s <= transport far_out_s after return_delay_c;

  near: nsl_mii.sgmii.sgmii_serdes_backend
    port map(
      reset_n_i => reset_n_i,
      clock125_i => clock125_i,
      clock625_i => clock625_i,
      sgmii_i => near_m2p_s,
      sgmii_o => near_p2m_s,
      pair_diff_i => near_in_s,
      pair_diff_o => near_out_s
      );

  far: nsl_mii.sgmii.sgmii_serdes_backend
    port map(
      reset_n_i => reset_n_i,
      clock125_i => clock125_i,
      clock625_i => clock625_i,
      sgmii_i => far_m2p_s,
      sgmii_o => far_p2m_s,
      pair_diff_i => far_in_s,
      pair_diff_o => far_out_s
      );

  sweep: process
    constant ctxt : log_context := label_c;
    variable cycles_v : natural;
    variable guard_v : natural;
    variable frames_v : natural;
    -- Symbol the frame owes next, or -1 while hunting for a comma.
    variable expect_v : integer;
    variable worst_v : natural;
  begin
    done_o <= '0';
    restart_s <= '0';
    delay_s <= 0 ps;

    wait until reset_n_i = '1';

    worst_v := 0;

    for step in 0 to step_count_c-1 loop
      delay_s <= step * step_c;

      -- Make both ends forget what they had settled on, so each
      -- length is converged on from scratch rather than nudged from
      -- the answer to the previous one.
      restart_s <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(clock125_i);
      end loop;
      restart_s <= '0';

      cycles_v := 0;
      while far_p2m_s.align_ready /= '1' or far_framed_s /= '1' loop
        wait until rising_edge(clock125_i);
        cycles_v := cycles_v + 1;
        assert cycles_v < converge_budget_c
          report "a cable of " & to_string(step * step_c)
          & " never converged: the loop has been searching for "
          & integer'image(cycles_v) & " words, with alignment "
          & std_ulogic'image(far_p2m_s.align_ready)
          & " and framing " & std_ulogic'image(far_framed_s)
          severity failure;
      end loop;

      if cycles_v > worst_v then
        worst_v := cycles_v;
      end if;

      -- Converged is not recovered: the delay the loop settled on
      -- has to be one that reads the whole stream back.
      frames_v := 0;
      expect_v := -1;
      guard_v := 0;

      while frames_v < frame_count_c loop
        wait until rising_edge(clock125_i);

        guard_v := guard_v + 1;
        assert guard_v < 1024
          report "a cable of " & to_string(step * step_c)
          & " converged but only " & integer'image(frames_v) & " of "
          & integer'image(frame_count_c)
          & " frames came back out of it"
          severity failure;

        if expect_v < 0 then
          if far_p2m_s.code_err = '0'
            and far_p2m_s.symbol.control = '1'
            and far_p2m_s.symbol.data = comma_c.data then
            expect_v := 1;
          end if;
        else
          assert far_p2m_s.code_err = '0'
            report "a cable of " & to_string(step * step_c)
            & " gave an invalid code group at symbol "
            & integer'image(expect_v) & " of the frame"
            severity failure;

          assert far_p2m_s.symbol.control = '0'
            report "a cable of " & to_string(step * step_c)
            & " gave symbol " & integer'image(expect_v)
            & " of the frame as a control code"
            severity failure;

          assert far_p2m_s.symbol.data
            = std_ulogic_vector(to_unsigned(expect_v, 8))
            report "a cable of " & to_string(step * step_c)
            & " gave symbol " & integer'image(expect_v)
            & " of the frame as "
            & integer'image(to_integer(unsigned(far_p2m_s.symbol.data)))
            severity failure;

          expect_v := expect_v + 1;
          if expect_v = frame_symbol_count_c then
            expect_v := -1;
            frames_v := frames_v + 1;
            guard_v := 0;
          end if;
        end if;
      end loop;
    end loop;

    log_info(ctxt, "recovered the stream at all "
             & integer'image(step_count_c) & " cable lengths from 0 to "
             & to_string((step_count_c - 1) * step_c)
             & ", converging in at most " & integer'image(worst_v)
             & " words");

    done_o <= '1';
    wait;
  end process;

end architecture;
