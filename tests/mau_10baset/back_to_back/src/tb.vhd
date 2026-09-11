library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_8023, nsl_mii, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;

architecture arch of tb is

  constant clock_hz_c : natural := 120000000;
  constant clock_half_c : time := 4166666 fs;
  -- Link pulse period and link integrity timers are divided by this,
  -- 16ms link pulse period becomes 16us.
  constant slow_timer_div_c : natural := 1000;

  -- Cycles per bit time on the line.
  constant bit_cycles_c : natural := clock_hz_c / 10000000;
  -- Longest the pair may be driven by a station that must not start a
  -- frame.  A deferring station still emits link pulses, those are one
  -- bit time long.
  constant defer_tx_max_c : natural := bit_cycles_c + 4;

  -- Propagation delay of the pair.
  constant line_delay_c : time := 10 ns;
  -- Time the comparator keeps its last output after the driver
  -- released the pair, before the transformer settles the pair back
  -- to its bias point.
  constant line_settle_c : time := 200 ns;

  constant frame_a0_c : byte_string
    := from_hex("a54dca182530bb1d6d132cded6237b2ed91e3f72");
  constant frame_a1_c : byte_string
    := from_hex("1fcb1971174494d6493c9d5c3460be31201e69fedaa0eee8"
                &"b9997f5c7c2999fdafe593253cd654af4dfad71427a0");
  constant frame_a2_c : byte_string
    := from_hex("aeb3fee9232f8af2211f9ee491c5b10becb5563bfc1e6f93427ecbc8fe29");
  constant frame_a3_c : byte_string
    := from_hex("3d7c2b1908ea4f6650c3971ebb2a44d70f5e8c136972a0b4de11");
  constant frame_a4_c : byte_string
    := from_hex("c81ba4f27e390d5566b2ec41903fd7a82c64e5bb17708f9a23d1");
  constant frame_a5_c : byte_string
    := from_hex("6f24e0ab935c7d18420ecf7361b5a9d2380c1e4477fabe5590d3");
  -- Longer than a slot time, so that a collision may happen late.
  constant frame_a6_c : byte_string
    := from_hex("b907e52e58d1a5fa81458a2cdfc13ef8a2e91dd451d746c20c8f"
                &"1c785a5e08b1206cf55ff15d37b8827253f3a8b87efea620d42d"
                &"a47e58d00baaf3eab8954c1852af870768eaa80b69931d66d425"
                &"922144ca033fab78a03c85968f11583b38e2ef52868b5202bf36"
                &"98a8fd34b1b5a2b91de213c8b4182825");
  constant frame_a7_c : byte_string
    := from_hex("40479749bf0627b6825ee4379f3b97d6c1c4c09343c6d87269b2");

  constant frame_b0_c : byte_string
    := from_hex("55e5cd8e46dc8ed4b7c2764d2a5a4d767706f85d8690024a");
  constant frame_b1_c : byte_string
    := from_hex("d6bda3401be9c8cbccc935f6cd1f61226ae15338ae1a3400"
                &"4d33ba0d246ac04c81b1baf23e3bf9eef5f79f2b4934af87"
                &"f5520b69b94b0d982e85bb55");
  constant frame_b2_c : byte_string
    := from_hex("b672a872637acd7466fcb60e0e8ff18463b0e4b2ba29703474f064ac68f700f5");
  constant frame_b3_c : byte_string
    := from_hex("9a03f5c7612d84be0f77e2cb35d190a4487c6b1efd2059a3c806");
  constant frame_b4_c : byte_string
    := from_hex("7e5910c2a6d48b3f1c0572ef94ba63d80e2117cc45f9a7302b6d");
  constant frame_b5_c : byte_string
    := from_hex("12ae76f39b5d04c8e1372a90bc6f58d34e0ba2179c31fe64d785");
  constant frame_b6_c : byte_string
    := from_hex("65fe1d9f97a1b685182dff57a0073c476e4fe2eec2ec103b17595a84283f");

  signal clock_s, reset_n_s, b_reset_n_s : std_ulogic;

  signal a_tx_p_s, a_tx_n_s, a_tx_en_s, a_rx_line_s : std_ulogic;
  signal b_tx_p_s, b_tx_n_s, b_tx_en_s, b_rx_line_s : std_ulogic;

  signal a_tx_flit_s, a_rx_flit_s : nsl_mii.flit.mii_flit_t;
  signal b_tx_flit_s, b_rx_flit_s : nsl_mii.flit.mii_flit_t;
  signal a_tx_ready_s, a_rx_valid_s : std_ulogic;
  signal b_tx_ready_s, b_rx_valid_s : std_ulogic;

  signal a_tx_bus_s, a_rx_bus_s : nsl_bnoc.committed.committed_bus;
  signal b_tx_bus_s, b_rx_bus_s : nsl_bnoc.committed.committed_bus;

  signal a_link_up_s, b_link_up_s : std_ulogic;
  signal a_polarity_s, b_polarity_s : std_ulogic;
  signal a_crs_s, b_crs_s, a_col_s, b_col_s : std_ulogic;
  signal a_collision_s, b_collision_s : std_ulogic;
  signal a_late_collision_s, b_late_collision_s : std_ulogic;
  signal a_excessive_collision_s, b_excessive_collision_s : std_ulogic;

  signal start_a2b_s : std_ulogic := '0';
  signal start_b2a_s : std_ulogic := '0';
  signal a2b_done_s : std_ulogic := '0';
  signal b2a_done_s : std_ulogic := '0';
  signal watch_b_rx_s : std_ulogic := '0';
  signal crs_b_rx_seen_s : std_ulogic := '0';
  signal col_seen_s : std_ulogic := '0';
  signal cut_a2b_s : std_ulogic := '0';

  -- Deference scenario: A transmits, B is handed a frame meanwhile.
  signal start_defer_a_s : std_ulogic := '0';
  signal start_defer_b_s : std_ulogic := '0';
  signal defer_a_done_s : std_ulogic := '0';
  signal defer_b_done_s : std_ulogic := '0';
  signal watch_defer_s : std_ulogic := '0';
  signal defer_violation_s : std_ulogic := '0';

  -- Collision scenarios: both stations start at the same time.
  signal start_collide_s : std_ulogic := '0';
  signal start_collide2_s : std_ulogic := '0';
  signal collide_a_done_s : std_ulogic := '0';
  signal collide_b_done_s : std_ulogic := '0';
  signal collide2_a_done_s : std_ulogic := '0';
  signal collide2_b_done_s : std_ulogic := '0';

  -- Late collision scenario: the A to B pair is cut, so B cannot hear
  -- A and starts a frame in the middle of A's, way past its slot time.
  signal start_late_a_s : std_ulogic := '0';
  signal start_late_b_s : std_ulogic := '0';
  signal start_late_a2_s : std_ulogic := '0';
  signal late_a_done_s : std_ulogic := '0';
  signal late_b_done_s : std_ulogic := '0';

  -- A is driving the pair for longer than a link pulse.
  signal a_sending_s : std_ulogic := '0';

  signal a_collision_count_s : natural := 0;
  signal b_collision_count_s : natural := 0;
  signal late_collision_seen_s : std_ulogic := '0';
  signal excessive_collision_seen_s : std_ulogic := '0';
  -- Simulation time of the last collision seen on either side.
  signal last_collision_s : time := 0 ns;
  -- Widest interval between the two stations restarting a frame after
  -- a collision.  Peers retrying in lockstep would keep this at zero.
  signal retry_split_s : time := 0 ns;

  -- Discards collision fragments, then checks the next frame of the
  -- expected length.  A collision aborts the peer frame in its
  -- preamble; whatever the receiver makes of the truncated preamble
  -- and the jam sequence is a runt that a real MAC drops on length or
  -- FCS.
  procedure frame_check_after_fragments(
    constant log_context : in string;
    signal req : in nsl_bnoc.committed.committed_req;
    signal ack : out nsl_bnoc.committed.committed_ack;
    signal clock : in std_ulogic;
    constant data : in byte_string) is
    variable rx : byte_stream;
    variable rx_valid : boolean;
  begin
    loop
      committed_get(req, ack, clock, rx, rx_valid);
      exit when rx.all'length = data'length;
      log_info(log_context & ": dropping a " & integer'image(rx.all'length)
               & " byte collision fragment");
      deallocate(rx);
    end loop;

    committed_assert(log_context, rx.all, rx_valid, data, true, LOG_LEVEL_FATAL);
    deallocate(rx);
  end procedure;

begin

  clock_gen: process is
  begin
    clock_s <= '0';
    wait for clock_half_c;
    clock_s <= '1';
    wait for clock_half_c;
  end process;

  reset_gen: process is
  begin
    reset_n_s <= '0';
    b_reset_n_s <= '0';
    wait for 20 * 2 * clock_half_c;
    wait until falling_edge(clock_s);
    reset_n_s <= '1';

    -- Two stations never leave reset on the same clock cycle.  The
    -- backoff pseudo-random source of a MAU free-runs from its own
    -- reset, this is what makes two peers draw different backoffs.
    for i in 1 to 37
    loop
      wait until falling_edge(clock_s);
    end loop;
    b_reset_n_s <= '1';

    wait;
  end process;

  -- Line model, A to B, straight pair.  While the pair is driven,
  -- comparator follows the differential value.  Once the driver
  -- releases the pair, comparator keeps its value for a while, then
  -- the pair settles back to its bias point.
  a_to_b: process(a_tx_p_s, a_tx_en_s, cut_a2b_s) is
  begin
    if cut_a2b_s = '0' and a_tx_en_s = '1' then
      b_rx_line_s <= transport a_tx_p_s after line_delay_c;
    else
      b_rx_line_s <= transport '0' after line_delay_c + line_settle_c;
    end if;
  end process;

  -- Line model, B to A, pair legs are swapped.
  b_to_a: process(b_tx_p_s, b_tx_en_s) is
  begin
    if b_tx_en_s = '1' then
      a_rx_line_s <= transport not b_tx_p_s after line_delay_c;
    else
      a_rx_line_s <= transport '1' after line_delay_c + line_settle_c;
    end if;
  end process;

  a_tx_gen: nsl_mii.flit.mii_flit_from_committed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      committed_i => a_tx_bus_s.req,
      committed_o => a_tx_bus_s.ack,

      flit_o => a_tx_flit_s,
      ready_i => a_tx_ready_s
      );

  a_rx_sink: nsl_mii.flit.mii_flit_to_committed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      flit_i => a_rx_flit_s,
      valid_i => a_rx_valid_s,

      committed_o => a_rx_bus_s.req,
      committed_i => a_rx_bus_s.ack
      );

  a_mau: nsl_8023.mau_10baset.mau_10baset_mau
    generic map(
      clock_i_hz_c => clock_hz_c,
      slow_timer_div_c => slow_timer_div_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      rx_i => a_rx_line_s,
      tx_p_o => a_tx_p_s,
      tx_n_o => a_tx_n_s,
      tx_en_o => a_tx_en_s,

      flit_i => a_tx_flit_s,
      ready_o => a_tx_ready_s,

      flit_o => a_rx_flit_s,
      valid_o => a_rx_valid_s,

      link_up_o => a_link_up_s,
      polarity_inverted_o => a_polarity_s,
      crs_o => a_crs_s,
      col_o => a_col_s,

      collision_o => a_collision_s,
      late_collision_o => a_late_collision_s,
      excessive_collision_o => a_excessive_collision_s
      );

  b_tx_gen: nsl_mii.flit.mii_flit_from_committed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      committed_i => b_tx_bus_s.req,
      committed_o => b_tx_bus_s.ack,

      flit_o => b_tx_flit_s,
      ready_i => b_tx_ready_s
      );

  b_rx_sink: nsl_mii.flit.mii_flit_to_committed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      flit_i => b_rx_flit_s,
      valid_i => b_rx_valid_s,

      committed_o => b_rx_bus_s.req,
      committed_i => b_rx_bus_s.ack
      );

  b_mau: nsl_8023.mau_10baset.mau_10baset_mau
    generic map(
      clock_i_hz_c => clock_hz_c,
      slow_timer_div_c => slow_timer_div_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => b_reset_n_s,

      rx_i => b_rx_line_s,
      tx_p_o => b_tx_p_s,
      tx_n_o => b_tx_n_s,
      tx_en_o => b_tx_en_s,

      flit_i => b_tx_flit_s,
      ready_o => b_tx_ready_s,

      flit_o => b_rx_flit_s,
      valid_o => b_rx_valid_s,

      link_up_o => b_link_up_s,
      polarity_inverted_o => b_polarity_s,
      crs_o => b_crs_s,
      col_o => b_col_s,

      collision_o => b_collision_s,
      late_collision_o => b_late_collision_s,
      excessive_collision_o => b_excessive_collision_s
      );

  monitor: process(clock_s) is
    variable b_tx_run_v : natural := 0;
    -- Duration of the current transmission of each station, and when
    -- it started.  Anything longer than a link pulse is a frame.
    variable a_run_v, b_run_v : natural := 0;
    variable a_edge_v, b_edge_v : time := 0 ns;
    -- Start of the attempt each station took after the last collision.
    variable a_retry_v, b_retry_v : time := 0 ns;
  begin
    if rising_edge(clock_s) then
      if reset_n_s = '1' then
        if watch_b_rx_s = '1' and b_crs_s = '1' then
          crs_b_rx_seen_s <= '1';
        end if;

        if a_col_s = '1' or b_col_s = '1' then
          col_seen_s <= '1';
        end if;

        -- A station that must defer may only drive the pair for the
        -- duration of a link pulse.
        if watch_defer_s = '1' and a_tx_en_s = '1' and b_tx_en_s = '1' then
          b_tx_run_v := b_tx_run_v + 1;
          if b_tx_run_v > defer_tx_max_c then
            defer_violation_s <= '1';
          end if;
        else
          b_tx_run_v := 0;
        end if;

        if a_collision_s = '1' then
          a_collision_count_s <= a_collision_count_s + 1;
          last_collision_s <= now;
        end if;

        if b_collision_s = '1' then
          b_collision_count_s <= b_collision_count_s + 1;
          last_collision_s <= now;
        end if;

        if a_late_collision_s = '1' or b_late_collision_s = '1' then
          late_collision_seen_s <= '1';
        end if;

        if a_excessive_collision_s = '1' or b_excessive_collision_s = '1' then
          excessive_collision_seen_s <= '1';
        end if;

        if a_tx_en_s = '1' then
          if a_run_v = 0 then
            a_edge_v := now;
          end if;
          a_run_v := a_run_v + 1;
        else
          a_run_v := 0;
        end if;

        if b_tx_en_s = '1' then
          if b_run_v = 0 then
            b_edge_v := now;
          end if;
          b_run_v := b_run_v + 1;
        else
          b_run_v := 0;
        end if;

        if a_run_v > defer_tx_max_c then
          a_sending_s <= '1';
        else
          a_sending_s <= '0';
        end if;

        -- Start of the first attempt each station takes after the
        -- last collision.  Two peers retrying in lockstep would start
        -- them at the same time.
        if last_collision_s /= 0 ns then
          if a_run_v = defer_tx_max_c + 1 and a_retry_v < last_collision_s then
            a_retry_v := a_edge_v;
            if b_retry_v > last_collision_s
              and a_retry_v - b_retry_v > retry_split_s then
              retry_split_s <= a_retry_v - b_retry_v;
            end if;
          end if;

          if b_run_v = defer_tx_max_c + 1 and b_retry_v < last_collision_s then
            b_retry_v := b_edge_v;
            if a_retry_v > last_collision_s
              and b_retry_v - a_retry_v > retry_split_s then
              retry_split_s <= b_retry_v - a_retry_v;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  a_gen: process is
  begin
    a_tx_bus_s.req <= nsl_bnoc.committed.committed_req_idle_c;

    wait until start_a2b_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a0_c, true);
    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a1_c, true);
    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a2_c, true);

    wait until start_defer_a_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a3_c, true);

    wait until start_collide_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a4_c, true);

    wait until start_collide2_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a5_c, true);

    wait until start_late_a_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a6_c, true);

    wait until start_late_a2_s = '1';

    committed_put(a_tx_bus_s.req, a_tx_bus_s.ack, clock_s, frame_a7_c, true);

    wait;
  end process;

  b_chk: process is
  begin
    b_rx_bus_s.ack <= nsl_bnoc.committed.committed_ack_idle_c;

    wait until start_a2b_s = '1';

    committed_check("A->B 0", b_rx_bus_s.req, b_rx_bus_s.ack, clock_s,
                    frame_a0_c, true, LOG_LEVEL_FATAL);
    committed_check("A->B 1", b_rx_bus_s.req, b_rx_bus_s.ack, clock_s,
                    frame_a1_c, true, LOG_LEVEL_FATAL);
    committed_check("A->B 2", b_rx_bus_s.req, b_rx_bus_s.ack, clock_s,
                    frame_a2_c, true, LOG_LEVEL_FATAL);

    a2b_done_s <= '1';

    committed_check("A->B defer", b_rx_bus_s.req, b_rx_bus_s.ack, clock_s,
                    frame_a3_c, true, LOG_LEVEL_FATAL);

    defer_a_done_s <= '1';

    frame_check_after_fragments("A->B collision", b_rx_bus_s.req,
                                b_rx_bus_s.ack, clock_s, frame_a4_c);

    collide_a_done_s <= '1';

    frame_check_after_fragments("A->B collision 2", b_rx_bus_s.req,
                                b_rx_bus_s.ack, clock_s, frame_a5_c);

    collide2_a_done_s <= '1';

    -- Frame abandoned on the late collision was cut from B anyway,
    -- only the one A sends afterwards must show up.
    frame_check_after_fragments("A->B after late", b_rx_bus_s.req,
                                b_rx_bus_s.ack, clock_s, frame_a7_c);

    late_a_done_s <= '1';

    wait;
  end process;

  b_gen: process is
  begin
    b_tx_bus_s.req <= nsl_bnoc.committed.committed_req_idle_c;

    wait until start_b2a_s = '1';

    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b0_c, true);
    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b1_c, true);
    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b2_c, true);

    wait until start_defer_b_s = '1';

    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b3_c, true);

    wait until start_collide_s = '1';

    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b4_c, true);

    wait until start_collide2_s = '1';

    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b5_c, true);

    wait until start_late_b_s = '1';

    committed_put(b_tx_bus_s.req, b_tx_bus_s.ack, clock_s, frame_b6_c, true);

    wait;
  end process;

  a_chk: process is
  begin
    a_rx_bus_s.ack <= nsl_bnoc.committed.committed_ack_idle_c;

    wait until start_b2a_s = '1';

    committed_check("B->A 0", a_rx_bus_s.req, a_rx_bus_s.ack, clock_s,
                    frame_b0_c, true, LOG_LEVEL_FATAL);
    committed_check("B->A 1", a_rx_bus_s.req, a_rx_bus_s.ack, clock_s,
                    frame_b1_c, true, LOG_LEVEL_FATAL);
    committed_check("B->A 2", a_rx_bus_s.req, a_rx_bus_s.ack, clock_s,
                    frame_b2_c, true, LOG_LEVEL_FATAL);

    b2a_done_s <= '1';

    committed_check("B->A defer", a_rx_bus_s.req, a_rx_bus_s.ack, clock_s,
                    frame_b3_c, true, LOG_LEVEL_FATAL);

    defer_b_done_s <= '1';

    frame_check_after_fragments("B->A collision", a_rx_bus_s.req,
                                a_rx_bus_s.ack, clock_s, frame_b4_c);

    collide_b_done_s <= '1';

    frame_check_after_fragments("B->A collision 2", a_rx_bus_s.req,
                                a_rx_bus_s.ack, clock_s, frame_b5_c);

    collide2_b_done_s <= '1';

    -- A hears B while jamming and draining, this one must be intact.
    frame_check_after_fragments("B->A late", a_rx_bus_s.req,
                                a_rx_bus_s.ack, clock_s, frame_b6_c);

    late_b_done_s <= '1';

    wait;
  end process;

  watchdog: process is
  begin
    wait for 5 ms;
    assert false
      report "Testbench timeout"
      severity failure;
    wait;
  end process;

  control: process is
  begin
    wait until reset_n_s = '1';

    if a_link_up_s /= '1' or b_link_up_s /= '1' then
      wait until a_link_up_s = '1' and b_link_up_s = '1' for 200 us;
    end if;

    assert a_link_up_s = '1' and b_link_up_s = '1'
      report "Link did not come up from link pulse exchange"
      severity failure;
    log_info("Link up on both ends at " & time'image(now));

    watch_b_rx_s <= '1';
    start_a2b_s <= '1';
    wait until a2b_done_s = '1';
    watch_b_rx_s <= '0';

    assert crs_b_rx_seen_s = '1'
      report "CRS never asserted at B while receiving"
      severity failure;

    start_b2a_s <= '1';
    wait until b2a_done_s = '1';

    assert a_polarity_s = '1'
      report "A did not resolve the swapped pair polarity"
      severity failure;
    assert b_polarity_s = '0'
      report "B reported an inverted pair polarity"
      severity failure;
    assert col_seen_s = '0'
      report "Collision was reported without concurrent transmission"
      severity failure;
    assert a_link_up_s = '1' and b_link_up_s = '1'
      report "Link went down during traffic"
      severity failure;

    -- Deference: while A transmits, B is handed a frame.  B must hold
    -- the pair until the medium has been free for an inter-frame gap.
    watch_defer_s <= '1';
    start_defer_a_s <= '1';
    -- Well into A's frame.
    wait for 20 us;
    start_defer_b_s <= '1';
    wait until defer_a_done_s = '1' and defer_b_done_s = '1';
    watch_defer_s <= '0';

    assert defer_violation_s = '0'
      report "B drove the pair for more than a link pulse while deferring"
      severity failure;
    assert col_seen_s = '0'
      report "A station transmitted a frame while the medium was busy"
      severity failure;
    assert a_collision_count_s = 0 and b_collision_count_s = 0
      report "Collision reported while stations took turns"
      severity failure;
    log_info("Deference verified at " & time'image(now));

    -- Collision: both stations start a frame at the same time.
    start_collide_s <= '1';
    wait until collide_a_done_s = '1' and collide_b_done_s = '1';

    log_info("Collision round 1 done at " & time'image(now)
             & ", collisions A: " & integer'image(a_collision_count_s)
             & ", B: " & integer'image(b_collision_count_s)
             & ", retries separated by " & time'image(retry_split_s));

    assert a_collision_count_s /= 0 and b_collision_count_s /= 0
      report "Simultaneous transmission did not report a collision on both sides"
      severity failure;
    assert late_collision_seen_s = '0'
      report "Collision in the preamble was reported as a late collision"
      severity failure;
    assert excessive_collision_seen_s = '0'
      report "Frame was abandoned after excessive collisions"
      severity failure;
    assert a_collision_count_s < 8 and b_collision_count_s < 8
      report "Peers kept colliding, backoff did not separate them"
      severity failure;
    assert retry_split_s > 1 us
      report "Peers restarted their frames in lockstep after a collision"
      severity failure;

    -- Same again, the pseudo-random source is in another state now.
    start_collide2_s <= '1';
    wait until collide2_a_done_s = '1' and collide2_b_done_s = '1';

    log_info("Collision round 2 done at " & time'image(now)
             & ", collisions A: " & integer'image(a_collision_count_s)
             & ", B: " & integer'image(b_collision_count_s));

    assert late_collision_seen_s = '0'
      report "Collision in the preamble was reported as a late collision"
      severity failure;
    assert excessive_collision_seen_s = '0'
      report "Frame was abandoned after excessive collisions"
      severity failure;

    -- Late collision: B is deaf to A, it starts a frame in the middle
    -- of A's long one.  A must jam, report a late collision, discard
    -- the rest of the frame from the flit interface, and carry on.
    cut_a2b_s <= '1';
    wait for 5 us;
    start_late_a_s <= '1';
    wait until a_sending_s = '1';
    -- Way past the 51.2us slot time of A's frame.
    wait for 70 us;
    start_late_b_s <= '1';
    wait until late_b_done_s = '1';

    assert late_collision_seen_s = '1'
      report "Collision past the slot time was not reported as late"
      severity failure;
    assert excessive_collision_seen_s = '0'
      report "Late collision was reported as an excessive collision"
      severity failure;
    log_info("Late collision verified at " & time'image(now)
             & ", collisions A: " & integer'image(a_collision_count_s)
             & ", B: " & integer'image(b_collision_count_s));

    cut_a2b_s <= '0';
    -- Leaves A time to discard the tail of the abandoned frame.
    wait for 150 us;
    start_late_a2_s <= '1';
    wait until late_a_done_s = '1';
    log_info("Flit interface recovered from an abandoned frame at "
             & time'image(now));

    -- Link pulses alone must keep the link up.
    if a_link_up_s /= '1' or b_link_up_s /= '1' then
      wait until a_link_up_s = '1' and b_link_up_s = '1' for 200 us;
    end if;
    wait for 150 us;
    assert a_link_up_s = '1' and b_link_up_s = '1'
      report "Link went down while idle"
      severity failure;

    -- Losing the pair must bring the link down on that side only.
    cut_a2b_s <= '1';
    wait for 150 us;
    assert b_link_up_s = '0'
      report "Link stayed up at B after link pulses stopped"
      severity failure;
    assert a_link_up_s = '1'
      report "Link went down at A while still receiving link pulses"
      severity failure;

    cut_a2b_s <= '0';
    wait for 150 us;
    assert b_link_up_s = '1'
      report "Link did not come back up at B"
      severity failure;

    log_info("All tests passed at " & time'image(now));
    nsl_simulation.control.terminate(0);

    wait;
  end process;

end architecture;
