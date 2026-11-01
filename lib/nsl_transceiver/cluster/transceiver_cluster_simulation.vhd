library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, nsl_line_coding;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.target.all;
use nsl_transceiver.lane.all;

entity transceiver_cluster is
  generic(
    config_c : nsl_transceiver.cluster.config_t;
    ref_clock_c : integer_vector
    );
  port(
    reset_n_i : in std_ulogic;

    ref_clock_i : in std_ulogic_vector(0 to ref_clock_c'length-1);

    lane_tx_o : out nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);
    lane_rx_i : in nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);

    lane_tx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);
    lane_rx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);

    tx_m_i : in nsl_transceiver.lane.tx_master_vector(0 to config_c.lane_count-1);
    tx_s_o : out nsl_transceiver.lane.tx_slave_vector(0 to config_c.lane_count-1);
    rx_m_o : out nsl_transceiver.lane.rx_master_vector(0 to config_c.lane_count-1);
    rx_s_i : in nsl_transceiver.lane.rx_slave_vector(0 to config_c.lane_count-1);

    pma_reset_n_i : in std_ulogic_vector(0 to config_c.lane_count-1);

    -- APB clock for the user-facing master. Sourced internally from
    -- the "stableclk" reference clock, which runs independently of
    -- the transceiver and is therefore available while the lanes are
    -- held in reset.
    apb_clock_o : out std_ulogic;
    apb_reset_n_i : in std_ulogic;
    apb_m_i : in nsl_amba.apb.master_t;
    apb_s_o : out nsl_amba.apb.slave_t
    );
end entity;

-- Behavioural backend. No vendor primitive exists for it: it models
-- a transceiver quad directly, so the portable contract can be
-- exercised by a testbench instead of only on a board.
--
-- What it models, per lane: 8b/10b encode and decode over a serial
-- pad pair at the configured line rate, comma alignment on the
-- configured comma symbol, an elastic buffer that really inserts and
-- drops the configured clock-correction sequence and reports it,
-- polarity inversion in both directions, PLL lock timing driven by
-- the reference clock the configuration names, and the alignment
-- restart handshake.
--
-- It is deliberately strict. Where the portable contract says a
-- field has to be valid, a lane driven with 'U' or 'X' there fails
-- the simulation rather than propagating the value: a backend that
-- forgets to drive an output is the defect this model exists to
-- catch, and an undriven std_ulogic compares equal to nothing.
--
-- Two reads of lane.sync_t are the model's own, because no backend
-- had made them before:
--
-- - the first byte of each pattern names a control symbol and the
--   rest name data symbols, which is the shape every 8b/10b
--   protocol uses (1000BASE-X aligns on /K28.5/ and rate-matches on
--   /K28.5/D16.2/);
-- - a lane configured with no clock-correction sequence cannot
--   absorb a rate difference at all, so rather than silently
--   corrupt the stream the model reports the overrun.
architecture simulation of transceiver_cluster is

  -- Symbols travel from the bit recovery process to the word process
  -- through a store, which is where the elastic buffer lives.
  type rx_symbol_t is
  record
    sym : nsl_line_coding.ibm_8b10b.data_t;
    code_error : std_ulogic;
    disparity_error : std_ulogic;
    disparity : std_ulogic;
  end record;

  type rx_symbol_vector is array (natural range <>) of rx_symbol_t;

  constant store_depth_c : natural := 64;

  -- Long enough for the fabric to see the lane come up, short enough
  -- not to dominate a testbench's run time.
  constant pll_lock_delay_c : time := 200 ns;
  constant pma_lock_delay_c : time := 100 ns;

  -- A line that holds its value for this long has nothing driving
  -- it. How long that is depends on what the lane carries, because
  -- the whole judgement rests on the coding promising to move the
  -- line: an 8b/10b stream transitions at least every five bits, a
  -- test pattern holds its line for as long as its order, and a raw
  -- lane promises nothing at all.
  function elec_idle_bit_count(encoding : encoding_t) return natural
  is
  begin
    case encoding is
      when ENCODING_8B10B =>
        return 20;
      when ENCODING_PRBS =>
        return 4 * nsl_transceiver.prbs.max_order_c;
      when others =>
        -- Long enough that a raw lane sending a run of zeros on
        -- purpose is not mistaken for a dead one, short enough that
        -- a dead one is still noticed.
        return 256;
    end case;
  end function;

  function symbol_bit_count(encoding : encoding_t) return natural
  is
  begin
    case encoding is
      when ENCODING_RAW =>
        return 8;
      when ENCODING_8B10B =>
        return 10;
      when ENCODING_PRBS =>
        -- A test pattern is raw bits, so a word is just its bytes.
        return 8;
      when others =>
        -- The model would have to carry a scrambler and a block sync
        -- state machine, and no backend in the library drives these
        -- encodings yet.
        assert false
          report "transceiver_cluster/simulation: "
          & encoding_t'image(encoding) & " is not modelled"
          severity failure;
        return 0;
    end case;
  end function;

  function bit_period(lane_index : natural) return time
  is
  begin
    return 1000000000 fs / config_c.lanes(lane_index).line_rate_mbps;
  end function;

  function word_period(lane_index : natural) return time
  is
  begin
    return bit_period(lane_index)
      * symbol_bit_count(config_c.lanes(lane_index).encoding)
      * config_c.lanes(lane_index).data_byte_count;
  end function;

  -- Position of the housekeeping clock in the refclk binding, or -1
  -- when the cluster was given no such clock. Unlike
  -- cluster.refclk_port this does not fail on absence: a model has
  -- somewhere else to get a clock from, where a primitive does not.
  function stable_clock_port return integer
  is
  begin
    for i in ref_clock_c'range loop
      if ref_clock_c(i) = clock_id("stableclk") then
        return i - ref_clock_c'low;
      end if;
    end loop;
    return -1;
  end function;

  constant stable_clock_port_c : integer := stable_clock_port;

  signal apb_clock_s : std_ulogic;
  signal pll_locked_s : std_ulogic_vector(0 to config_c.pll_count-1);

begin

  -- A configuration the portable contract rejects would be rejected
  -- by a vendor architecture too, and getting the same answer out of
  -- both is half of what makes the contract portable.
  assert nsl_transceiver.cluster.is_valid(config_c)
    report "transceiver_cluster/simulation: the configuration is not valid"
    severity failure;

  assert config_c.lane_count <= nsl_transceiver.cluster.max_lane_count_c
    report "transceiver_cluster/simulation: more lanes than a cluster can hold"
    severity failure;

  -- Reference clocks -----------------------------------------------

  -- The housekeeping clock is what a backend times its reset
  -- sequence and its configuration bus on, so the model runs the
  -- configuration bus on it when the cluster has one and generates
  -- one otherwise.
  with_stable_clock: if stable_clock_port_c >= 0 generate
    apb_clock_s <= ref_clock_i(stable_clock_port_c);
  end generate;

  without_stable_clock: if stable_clock_port_c < 0 generate
    gen: process
    begin
      apb_clock_s <= '0';
      wait for 5 ns;
      apb_clock_s <= '1';
      wait for 5 ns;
    end process;
  end generate;

  apb_clock_o <= apb_clock_s;

  -- Like the GT backends, this one has no register bus to offer the
  -- portable contract: everything it models comes from the
  -- configuration. The bus is still answered so a master shared with
  -- other slaves does not stall on this one; every access takes an
  -- error response.
  csr: nsl_amba.apb.apb_slave
    generic map(
      config_c => nsl_transceiver.cluster.csr_config_c
      )
    port map(
      clock_i => apb_clock_s,
      reset_n_i => apb_reset_n_i,

      apb_i => apb_m_i,
      apb_o => apb_s_o,

      address_o => open,

      w_data_o => open,
      w_mask_o => open,
      w_error_i => '1',
      w_valid_o => open,

      r_data_i => (others => x"00"),
      r_ready_o => open,
      r_error_i => '1'
      );

  -- A PLL cannot lock to a clock that is not running, and a
  -- testbench that forgot to drive one would otherwise see a lane
  -- that simply never comes up.
  pll_gen: for pll_idx in 0 to config_c.pll_count-1 generate

    enabled_pll: if config_c.plls(pll_idx).enabled generate

      -- ref_clock_index is a position in the cluster's ref_clock_c
      -- binding, not a target clock identifier: the identifiers are
      -- what the binding holds.
      constant port_c : natural := config_c.plls(pll_idx).ref_clock_index;

      constant ref_period_c : time
        := 1000000000 fs / config_c.plls(pll_idx).ref_clock_mhz;

    begin

      lock: process
      begin
        pll_locked_s(pll_idx) <= '0';

        wait until reset_n_i = '1';

        -- Give it a few reference periods to notice, then insist.
        for i in 0 to 3 loop
          wait on ref_clock_i(port_c) for 4 * ref_period_c;
          assert ref_clock_i(port_c)'event
            report "transceiver_cluster/simulation: pll "
            & integer'image(pll_idx) & " is configured for the "
            & integer'image(config_c.plls(pll_idx).ref_clock_mhz)
            & " MHz clock on reference port "
            & integer'image(config_c.plls(pll_idx).ref_clock_index)
            & ", which is not running"
            severity failure;
        end loop;

        wait for pll_lock_delay_c;

        pll_locked_s(pll_idx) <= '1';

        wait until reset_n_i = '0';
      end process;

    end generate;

    disabled_pll: if not config_c.plls(pll_idx).enabled generate
      pll_locked_s(pll_idx) <= '0';
    end generate;

  end generate;

  -- Lanes ----------------------------------------------------------

  lane_gen: for lane_idx in 0 to config_c.lane_count-1 generate

    enabled_lane: if config_c.lanes(lane_idx).enabled generate

      constant cfg_c : nsl_transceiver.lane.config_t
        := config_c.lanes(lane_idx);
      constant byte_count_c : natural := cfg_c.data_byte_count;
      constant sym_bits_c : natural := symbol_bit_count(cfg_c.encoding);
      constant bit_period_c : time := bit_period(lane_idx);
      constant word_period_c : time := word_period(lane_idx);
      constant guard_c : time := bit_period_c / 8;
      constant elec_idle_bit_count_c : natural
        := elec_idle_bit_count(cfg_c.encoding);

      -- Fill the elastic buffer holds when nothing disturbs it.
      -- A few words of slack in each direction: enough that a
      -- partner running at a slightly different rate is absorbed by
      -- the clock-correction sequence rather than by an underrun,
      -- and small enough that the lane's latency stays plausible.
      constant store_target_c : natural := byte_count_c * 4;

      signal word_clock_s : std_ulogic;
      signal lane_reset_n_s : std_ulogic;

      signal tx_serial_s : std_ulogic;
      signal rx_serial_s : std_ulogic;

      signal store_s : rx_symbol_vector(0 to store_depth_c-1);
      signal store_wptr_s : natural range 0 to store_depth_c-1;
      signal store_rptr_s : natural range 0 to store_depth_c-1;

      signal aligned_s : std_ulogic;
      signal pma_locked_s : std_ulogic;
      signal elec_idle_s : std_ulogic;

      -- What the receive side recovered, before it is decided
      -- whether the fabric is given it or a pattern checker is.
      signal rx_data_s : byte_string(0 to nsl_transceiver.lane.max_data_byte_count_c-1);
      signal rx_aux_s : nsl_transceiver.lane.data_aux_t;
      signal rx_valid_s : std_ulogic;
      signal rx_aligned_s : std_ulogic;
      signal rx_corrected_s : std_ulogic;
      signal rx_status_s : nsl_transceiver.lane.status_t;

    begin

      lane_reset_n_s <= reset_n_i and pma_reset_n_i(lane_idx)
                        and pll_locked_s(cfg_c.pll_index);

      -- The elastic buffer absorbs the difference between the
      -- recovered clock and the transmit clock, so the lane presents
      -- the same clock in both directions, exactly as a vendor quad
      -- with its buffers enabled does.
      clock: process
      begin
        word_clock_s <= '0';
        wait for word_period_c / 2;
        word_clock_s <= '1';
        wait for word_period_c - word_period_c / 2;
      end process;

      lane_tx_clock_o(lane_idx) <= word_clock_s;
      lane_rx_clock_o(lane_idx) <= word_clock_s;

      -- Transmit -----------------------------------------------------

      -- A lane carrying a protocol serialises what the fabric gave
      -- it; one carrying a test pattern serialises what its own
      -- generator produced, and never looks at the data bus. Only
      -- one of the two is built, because they are coding models of
      -- the lane rather than layers over it.
      coded_tx: if cfg_c.encoding /= ENCODING_PRBS generate
      begin


        -- A word is sampled on each rising edge of the lane clock and
        -- shifted out over exactly one word period, so the serialiser
        -- stays in phase with the clock without ever waiting on it
        -- again: a process landing on the edge and then waiting for it
        -- would race the clock's own update and be a word late or
        -- early depending on the simulator.
        tx: process
          variable disparity_v : std_ulogic;
          variable sym_v : nsl_line_coding.ibm_8b10b.data_t;
          variable group_v : nsl_line_coding.ibm_8b10b.code_word_t;
          variable word_v : nsl_line_coding.ibm_8b10b.data_vector(0 to byte_count_c-1);
          -- Captured with the word: the adapter is entitled to change
          -- them as soon as the edge has passed.
          variable force_v : std_ulogic_vector(0 to byte_count_c-1);
          variable force_to_v : std_ulogic_vector(0 to byte_count_c-1);
          variable bit_v : std_ulogic;
          variable idle_phase_v : natural;
        begin
          tx_serial_s <= '0';
          disparity_v := '0';
          idle_phase_v := 0;

          wait until lane_reset_n_s = '1';
          wait until rising_edge(word_clock_s);

          while lane_reset_n_s = '1' loop
            -- A lane whose sideband is unknown is a lane whose partner
            -- decodes something arbitrary, so say so here rather than
            -- let the value travel.
            assert tx_m_i(lane_idx).valid = '0' or tx_m_i(lane_idx).valid = '1'
              report "transceiver_cluster/simulation: lane "
              & integer'image(lane_idx) & " has no transmit valid"
              severity failure;

            force_v := (others => '0');
            force_to_v := (others => '0');

            if tx_m_i(lane_idx).valid = '1' then
              for i in 0 to byte_count_c-1 loop
                assert tx_m_i(lane_idx).aux(i)(0) = '0'
                  or tx_m_i(lane_idx).aux(i)(0) = '1'
                  report "transceiver_cluster/simulation: lane "
                  & integer'image(lane_idx) & " byte " & integer'image(i)
                  & " has no control flag in aux bit 0"
                  severity failure;

                word_v(i).data := tx_m_i(lane_idx).data(i);
                word_v(i).control := tx_m_i(lane_idx).aux(i)(0);

                if cfg_c.encoding = ENCODING_8B10B
                  and tx_m_i(lane_idx).aux(i)(1) = '1' then
                  force_v(i) := '1';
                  force_to_v(i) := tx_m_i(lane_idx).aux(i)(2);
                end if;
              end loop;

              -- The idle sequence restarts whenever the lane stops
              -- sending it, so a partner always sees it whole.
              idle_phase_v := 0;
            else
              -- Nothing to send: the configured idle goes out, so the
              -- partner keeps its alignment and its disparity. The
              -- sequence advances across words, which is the only way
              -- a lane narrower than the pattern can send it at all.
              assert cfg_c.sync.idle_byte_count /= 0
                report "transceiver_cluster/simulation: lane "
                & integer'image(lane_idx) & " has nothing to transmit and"
                & " no idle pattern to send instead"
                severity failure;

              for i in 0 to byte_count_c-1 loop
                word_v(i).data := cfg_c.sync.idle_pattern(idle_phase_v);
                -- The first byte of a pattern names a control symbol.
                if idle_phase_v = 0 then
                  word_v(i).control := '1';
                else
                  word_v(i).control := '0';
                end if;
                idle_phase_v := (idle_phase_v + 1) mod cfg_c.sync.idle_byte_count;
              end loop;
            end if;

            for i in 0 to byte_count_c-1 loop
              sym_v := word_v(i);

              case cfg_c.encoding is
                when ENCODING_8B10B =>
                  -- A lane may ask for a disparity rather than take
                  -- the one the encoder would have picked: that is
                  -- what aux bits 1 and 2 are for.
                  if force_v(i) = '1' then
                    disparity_v := not force_to_v(i);
                  end if;

                  nsl_line_coding.ibm_8b10b_spec.encode(
                    sym_v, disparity_v, group_v, disparity_v);

                  -- A code group is indexed in transmission order.
                  for b in 0 to 9 loop
                    bit_v := group_v(b);
                    if cfg_c.polarity_invert_tx then
                      bit_v := not bit_v;
                    end if;
                    tx_serial_s <= bit_v;
                    wait for bit_period_c;
                  end loop;

                when others =>
                  for b in 0 to 7 loop
                    bit_v := sym_v.data(b);
                    if cfg_c.polarity_invert_tx then
                      bit_v := not bit_v;
                    end if;
                    tx_serial_s <= bit_v;
                    wait for bit_period_c;
                  end loop;
              end case;
            end loop;
          end loop;
        end process;

      end generate;

      pattern_tx: if cfg_c.encoding = ENCODING_PRBS generate

        signal word_s : byte_string(0 to byte_count_c-1);
        signal word_valid_s : std_ulogic;

      begin

        generator: nsl_transceiver.prbs.prbs_generator
          generic map(
            byte_count_c => byte_count_c
            )
          port map(
            clock_i => word_clock_s,
            reset_n_i => lane_reset_n_s,

            mode_i => tx_m_i(lane_idx).prbs_select,
            force_error_i => tx_m_i(lane_idx).prbs_force_error,
            -- The serialiser takes a word every word period.
            ready_i => '1',

            data_o => word_s,
            valid_o => word_valid_s
            );

        -- Same shape as the coded serialiser: a word is sampled on
        -- the edge and shifted out over exactly one word period, so
        -- the two stay in step without the serialiser ever waiting
        -- on the clock again.
        tx: process
          variable word_v : byte_string(0 to byte_count_c-1);
          variable valid_v : std_ulogic;
          variable bit_v : std_ulogic;
        begin
          tx_serial_s <= '0';

          wait until lane_reset_n_s = '1';
          wait until rising_edge(word_clock_s);

          while lane_reset_n_s = '1' loop
            word_v := word_s;
            valid_v := word_valid_s;

            for i in 0 to byte_count_c-1 loop
              for b in 0 to 7 loop
                if valid_v = '1' then
                  bit_v := word_v(i)(b);
                else
                  -- No pattern asked for, so the lane is held quiet
                  -- rather than made to carry something arbitrary.
                  bit_v := '0';
                end if;

                if cfg_c.polarity_invert_tx then
                  bit_v := not bit_v;
                end if;

                tx_serial_s <= bit_v;
                wait for bit_period_c;
              end loop;
            end loop;
          end loop;
        end process;

      end generate;

      lane_tx_o(lane_idx) <= nsl_io.diff.to_diff(tx_serial_s);

      -- Loopback -----------------------------------------------------

      no_loopback: if cfg_c.loopback = LOOPBACK_NONE generate
        rx_serial_s <= nsl_io.diff.to_se(lane_rx_i(lane_idx));
      end generate;

      pma_loopback: if cfg_c.loopback = LOOPBACK_NEAR_END_PMA generate
        -- The pads keep transmitting, as they do on a real quad: the
        -- receiver is what moves.
        rx_serial_s <= tx_serial_s;
      end generate;

      -- The remaining modes need a path the model does not have: the
      -- PCS modes bypass the serialiser, and the far-end modes
      -- retransmit what was received. Nothing in the library drives
      -- them yet, and a model that quietly behaved like
      -- LOOPBACK_NONE instead would be worse than none at all.
      unmodelled_loopback: if cfg_c.loopback /= LOOPBACK_NONE
        and cfg_c.loopback /= LOOPBACK_NEAR_END_PMA generate
        rx_serial_s <= 'U';

        complain: process
        begin
          assert false
            report "transceiver_cluster/simulation: lane "
            & integer'image(lane_idx) & " asks for "
            & loopback_mode_t'image(cfg_c.loopback)
            & ", which is not modelled"
            severity failure;
          wait;
        end process;
      end generate;

      -- Receive ------------------------------------------------------

      -- Recovers the bit stream, finds the symbol boundary, decodes,
      -- and leaves the symbols in the store for the word process.
      --
      -- The sampling phase follows the last transition seen, which
      -- is what a bang-bang recovery loop does and what lets the
      -- model work behind a channel of any delay. 8b/10b guarantees
      -- a transition at least every five bits, so the phase tracks a
      -- partner whose rate differs from this lane's.
      rx_bit: process
        variable to_centre_v : time;
        variable bit_v, line_v : std_ulogic;
        variable group_v : nsl_line_coding.ibm_8b10b.code_word_t;
        variable shift_v : std_ulogic_vector(0 to sym_bits_c-1);
        variable filled_v : natural;
        variable phase_v : natural;
        variable disparity_v : std_ulogic;
        variable entry_v : rx_symbol_t;
        variable sym_v : nsl_line_coding.ibm_8b10b.data_t;
        variable code_error_v, disparity_error_v : std_ulogic;
        variable comma_v : nsl_line_coding.ibm_8b10b.data_t;
        variable comma_mask_v : byte;
        variable wptr_v : natural range 0 to store_depth_c-1;
        -- Set by align_trigger: the next comma re-establishes the
        -- symbol boundary, wherever in the stream it turns up.
        variable rehunt_v : boolean;
      begin
        store_wptr_s <= 0;
        aligned_s <= '0';
        wptr_v := 0;
        shift_v := (others => '0');
        filled_v := 0;
        phase_v := 0;
        disparity_v := '0';
        rehunt_v := false;

        wait until lane_reset_n_s = '1';

        -- There is no recovered bit stream before the clock
        -- recovery loop has something to track, so a lane reports
        -- PMA lock before it reports alignment, never the other way
        -- round.
        wait until pma_locked_s = '1';

        -- Alignment hunts for the configured comma, so a lane that
        -- needs alignment and has no comma would hunt forever.
        if cfg_c.encoding = ENCODING_8B10B then
          assert cfg_c.sync.comma_byte_count = 1
            report "transceiver_cluster/simulation: lane "
            & integer'image(lane_idx) & " needs exactly one comma byte"
            & " to align on, the symbol the stream is framed by"
            severity failure;

          -- comma_negated describes a comma detector that matches a
          -- raw code group rather than a decoded symbol. This model
          -- decodes, and the two running-disparity forms of a
          -- control code are each other's complement, so its
          -- detector finds the comma on a swapped pair whether or
          -- not it is told to: there is nothing here for the field
          -- to change. Honouring it would also be a half-measure,
          -- because the data on a swapped pair does not come back
          -- the same either way, which is what polarity_invert_rx is
          -- for. Saying so beats quietly behaving as if the field
          -- fixed the lane.
          assert not cfg_c.sync.comma_negated
            report "transceiver_cluster/simulation: lane "
            & integer'image(lane_idx) & " asks for a negated comma,"
            & " which a model aligning on decoded symbols cannot"
            & " express; a swapped pair is undone by"
            & " polarity_invert_rx"
            severity failure;
          comma_v.data := cfg_c.sync.comma_value(0);
          comma_v.control := '1';
          comma_mask_v := cfg_c.sync.comma_mask(0);
        end if;

        -- The first transition gives the bit boundary.
        wait on rx_serial_s;
        to_centre_v := bit_period_c / 2;

        loop
          wait for to_centre_v;

          exit when lane_reset_n_s = '0';

          line_v := rx_serial_s;
          if cfg_c.polarity_invert_rx then
            line_v := not line_v;
          end if;
          bit_v := line_v;

          shift_v := shift_v(1 to sym_bits_c-1) & bit_v;
          if filled_v < sym_bits_c then
            filled_v := filled_v + 1;
          end if;

          -- A restart asks for the symbol boundary to be found
          -- again; it does not say the current one is wrong. A lane
          -- already framed on the comma therefore keeps delivering
          -- across the restart, and only a stream that really has
          -- slipped moves. Dropping alignment here instead would
          -- punch a hole in the stream every time a protocol asked,
          -- and a protocol that asks whenever it does not yet like
          -- what it receives would never be given the chance to.
          if rx_s_i(lane_idx).align_trigger = '1' then
            rehunt_v := true;
          end if;

          -- No signal on the line is no alignment to keep: a lane
          -- whose partner went away has to find the boundary again
          -- when it comes back. Only where there is a boundary to
          -- find, though: a lane with no comma in its stream has
          -- nothing to re-find and would only lose what it had
          -- buffered.
          if elec_idle_s = '1' and cfg_c.encoding = ENCODING_8B10B then
            aligned_s <= '0';
            rehunt_v := false;
            filled_v := 0;
          end if;

          if filled_v = sym_bits_c then
            if cfg_c.encoding = ENCODING_8B10B then
              -- The shift register runs oldest first and a code
              -- group is indexed in transmission order, so the two
              -- walk together rather than mirroring.
              for b in 0 to sym_bits_c-1 loop
                group_v(b) := shift_v(b);
              end loop;

              nsl_line_coding.ibm_8b10b_spec.decode(
                group_v, disparity_v, sym_v, entry_v.disparity,
                code_error_v, disparity_error_v);

              if aligned_s /= '1' then
                -- Hunting: every bit is a candidate boundary, and
                -- the comma is the symbol that confirms one.
                if code_error_v = '0' and sym_v.control = '1'
                  and (sym_v.data and comma_mask_v)
                     = (comma_v.data and comma_mask_v) then
                  aligned_s <= '1';
                  rehunt_v := false;
                  phase_v := 0;
                  disparity_v := entry_v.disparity;
                  entry_v.sym := sym_v;
                  entry_v.code_error := '0';
                  entry_v.disparity_error := '0';
                  store_s(wptr_v) <= entry_v;
                  wptr_v := (wptr_v + 1) mod store_depth_c;
                  store_wptr_s <= wptr_v;
                end if;
              elsif rehunt_v and code_error_v = '0'
                and sym_v.control = '1'
                and (sym_v.data and comma_mask_v)
                   = (comma_v.data and comma_mask_v) then
                -- The comma says where the boundary is, so the
                -- symbol it ends is this one whatever the phase
                -- counter had reached.
                rehunt_v := false;
                phase_v := 0;
                disparity_v := entry_v.disparity;
                entry_v.sym := sym_v;
                entry_v.code_error := '0';
                entry_v.disparity_error := '0';
                store_s(wptr_v) <= entry_v;
                wptr_v := (wptr_v + 1) mod store_depth_c;
                store_wptr_s <= wptr_v;
              else
                phase_v := (phase_v + 1) mod sym_bits_c;
                if phase_v = 0 then
                  disparity_v := entry_v.disparity;
                  entry_v.sym := sym_v;
                  entry_v.code_error := code_error_v;
                  entry_v.disparity_error := disparity_error_v;
                  store_s(wptr_v) <= entry_v;
                  wptr_v := (wptr_v + 1) mod store_depth_c;
                  store_wptr_s <= wptr_v;
                end if;
              end if;
            else
              -- A raw lane carries no symbol boundary of its own, so
              -- the one the model picks out of reset is as good as
              -- any other.
              aligned_s <= '1';
              phase_v := (phase_v + 1) mod sym_bits_c;
              if phase_v = 0 then
                for b in 0 to 7 loop
                  entry_v.sym.data(b) := shift_v(b);
                end loop;
                entry_v.sym.control := '0';
                entry_v.code_error := '0';
                entry_v.disparity_error := '0';
                entry_v.disparity := '0';
                store_s(wptr_v) <= entry_v;
                wptr_v := (wptr_v + 1) mod store_depth_c;
                store_wptr_s <= wptr_v;
              end if;
            end if;
          end if;

          -- Follow the next transition if one arrives close enough
          -- to the boundary to be one; otherwise keep the nominal
          -- phase and remember that we waited past it.
          wait on rx_serial_s for bit_period_c / 2 + guard_c;
          if rx_serial_s'event then
            to_centre_v := bit_period_c / 2;
          else
            to_centre_v := bit_period_c / 2 - guard_c;
          end if;
        end loop;
      end process;

      -- Lock and idle detection --------------------------------------

      pma: process
      begin
        pma_locked_s <= '0';
        elec_idle_s <= '1';

        wait until lane_reset_n_s = '1';

        -- Nothing on the line means nothing to lock to.
        wait on rx_serial_s;
        elec_idle_s <= '0';

        wait for pma_lock_delay_c;
        pma_locked_s <= '1';

        loop
          wait on rx_serial_s, lane_reset_n_s
            for elec_idle_bit_count_c * bit_period_c;

          exit when lane_reset_n_s = '0';

          if rx_serial_s'event then
            elec_idle_s <= '0';
          else
            elec_idle_s <= '1';
          end if;
        end loop;
      end process;

      -- Word presentation --------------------------------------------

      -- Pops one word per lane clock out of the store, inserting or
      -- dropping a clock-correction sequence to hold the fill where
      -- it belongs. This is the elastic buffer, and the only place
      -- rx_m_o.clock_corrected can come from.
      --
      -- The buffer fills to its target before it presents anything,
      -- so a stream arriving slightly slower than this lane's own
      -- clock has somewhere to borrow from. That is why alignment
      -- and the first valid word are a measurable distance apart on
      -- a real quad too.
      rx_word: process
        variable rptr_v : natural range 0 to store_depth_c-1;
        variable fill_v : natural;
        variable entry_v : rx_symbol_t;
        variable corrected_v : std_ulogic;
        variable primed_v : boolean;
        -- Bytes of the clock-correction sequence still owed to the
        -- fabric, and where in the sequence the next one comes from.
        variable insert_v : natural;
        variable insert_phase_v : natural;

        function fill_of(wptr : natural; rptr : natural) return natural
        is
        begin
          return (wptr - rptr + store_depth_c) mod store_depth_c;
        end function;

        -- Whether the sequence at the read pointer is the one the
        -- buffer is allowed to drop.
        -- Impure: it reads the store the writer side fills.
        impure function at_clock_correction(rptr : natural) return boolean
        is
          variable e_v : rx_symbol_t;
        begin
          if cfg_c.sync.clock_correction_byte_count = 0 then
            return false;
          end if;

          for i in 0 to cfg_c.sync.clock_correction_byte_count-1 loop
            e_v := store_s((rptr + i) mod store_depth_c);
            if e_v.sym.data /= cfg_c.sync.clock_correction_pattern(i) then
              return false;
            end if;
            if i = 0 and e_v.sym.control /= '1' then
              return false;
            end if;
          end loop;

          return true;
        end function;

        -- One byte of the clock-correction sequence, shaped like a
        -- symbol that came off the line, because that is what the
        -- fabric is about to be told it is.
        function correction_symbol(phase : natural) return rx_symbol_t
        is
          variable e_v : rx_symbol_t;
        begin
          e_v.sym.data := cfg_c.sync.clock_correction_pattern(phase);
          if phase = 0 then
            e_v.sym.control := '1';
          else
            e_v.sym.control := '0';
          end if;
          e_v.code_error := '0';
          e_v.disparity_error := '0';
          e_v.disparity := '0';
          return e_v;
        end function;
      begin
        rptr_v := 0;
        store_rptr_s <= 0;
        primed_v := false;
        insert_v := 0;
        insert_phase_v := 0;

        rx_valid_s <= '0';
        rx_aligned_s <= '0';
        rx_corrected_s <= '0';
        rx_status_s <= (others => '0');

        -- Bytes past the lane's width belong to no byte on this
        -- lane. They are driven from here rather than from a
        -- concurrent statement because a process assigning an array
        -- element under a dynamic index drives the whole array.
        for i in 0 to nsl_transceiver.lane.max_data_byte_count_c-1 loop
          rx_data_s(i) <= (others => '-');
          rx_aux_s(i) <= (others => '-');
        end loop;

        wait until lane_reset_n_s = '1';
        wait until rising_edge(word_clock_s);

        while lane_reset_n_s = '1' loop
          corrected_v := '0';

          if aligned_s /= '1' then
            -- Nothing has framed the stream yet, so there is no word
            -- to present and no fill worth keeping.
            rx_valid_s <= '0';
            rx_aligned_s <= '0';
            rptr_v := store_wptr_s;
            primed_v := false;
            insert_v := 0;
          else
            -- Alignment is reported from here rather than from the
            -- bit recovery side, so it means what an adapter needs
            -- it to mean: words are coming out. An adapter is
            -- entitled to read the data bus whenever the lane says
            -- it is aligned, and between finding the comma and
            -- filling the buffer there is nothing on it yet.
            fill_v := fill_of(store_wptr_s, rptr_v);

            -- A writer that laps the reader corrupts the stream
            -- without anything downstream being able to tell, so
            -- the fill is checked rather than left to wrap.
            assert fill_v <= store_depth_c - 2 * byte_count_c
              report "transceiver_cluster/simulation: lane "
              & integer'image(lane_idx) & " overran its elastic"
              & " buffer: its partner is sending faster than the"
              & " clock-correction sequence lets it drop"
              severity failure;

            if not primed_v then
              rx_valid_s <= '0';
              primed_v := fill_v >= store_target_c;
            else
              rx_aligned_s <= '1';

              -- Too full: a clock-correction sequence is what the
              -- buffer is permitted to lose, and the protocol above
              -- knows to expect it.
              while fill_v > store_target_c + byte_count_c
                and at_clock_correction(rptr_v) loop
                rptr_v := (rptr_v + cfg_c.sync.clock_correction_byte_count)
                          mod store_depth_c;
                fill_v := fill_of(store_wptr_s, rptr_v);
                corrected_v := '1';
              end loop;

              -- Running dry: the sequence at the read pointer is
              -- sent twice, which is the only thing the buffer may
              -- add. It cannot invent one in the middle of a frame
              -- any more than a real quad can: what it adds is a
              -- copy of what is already there, so the addition only
              -- ever lands where the protocol put a sequence.
              if fill_v < store_target_c and insert_v = 0
                and fill_v >= cfg_c.sync.clock_correction_byte_count
                and at_clock_correction(rptr_v) then
                insert_v := cfg_c.sync.clock_correction_byte_count;
                insert_phase_v := 0;
              end if;

              -- Nothing left and nothing to repeat. Either the
              -- partner is running away from this lane faster than
              -- its rate-matching sequence arrives, or it has no
              -- such sequence at all.
              assert fill_v >= byte_count_c or insert_v /= 0
                report "transceiver_cluster/simulation: lane "
                & integer'image(lane_idx) & " ran its elastic buffer"
                & " empty with no clock-correction sequence to"
                & " repeat, so the rate difference cannot be absorbed"
                severity failure;

              for i in 0 to byte_count_c-1 loop
                if insert_v /= 0 then
                  entry_v := correction_symbol(insert_phase_v);
                  insert_phase_v := insert_phase_v + 1;
                  insert_v := insert_v - 1;
                  corrected_v := '1';
                else
                  entry_v := store_s(rptr_v);
                  rptr_v := (rptr_v + 1) mod store_depth_c;
                end if;

                rx_data_s(i) <= entry_v.sym.data;
                rx_aux_s(i)(0) <= entry_v.sym.control;
                rx_aux_s(i)(1) <= entry_v.code_error;
                rx_aux_s(i)(2) <= entry_v.disparity_error;
                rx_aux_s(i)(3) <= entry_v.disparity;
                rx_aux_s(i)(aux_t'left downto 4) <= (others => '-');
              end loop;

              rx_valid_s <= '1';
            end if;
          end if;

          store_rptr_s <= rptr_v;
          rx_corrected_s <= corrected_v;

          wait until rising_edge(word_clock_s);
        end loop;
      end process;

      rx_m_o(lane_idx).pma_lock <= pma_locked_s;
      rx_m_o(lane_idx).elec_idle <= elec_idle_s;

      -- A lane carrying a protocol hands what it recovered to the
      -- fabric; one carrying a test pattern hands it to a checker
      -- instead and leaves the data bus alone. The two are coding
      -- models of the lane, so exactly one of them is built.
      coded_rx: if cfg_c.encoding /= ENCODING_PRBS generate
        rx_m_o(lane_idx).data <= rx_data_s;
        rx_m_o(lane_idx).aux <= rx_aux_s;
        rx_m_o(lane_idx).valid <= rx_valid_s;
        rx_m_o(lane_idx).pcs_aligned <= rx_aligned_s;
        rx_m_o(lane_idx).clock_corrected <= rx_corrected_s;
        rx_m_o(lane_idx).status <= rx_status_s;
        rx_m_o(lane_idx).prbs_locked <= '0';
        rx_m_o(lane_idx).prbs_error <= '0';
      end generate;

      pattern_rx: if cfg_c.encoding = ENCODING_PRBS generate

        signal locked_s, error_s : std_ulogic;

      begin

        -- The checker finds the pattern's phase in the bits
        -- themselves, so it does not care that the words it is
        -- given were framed wherever the receiver happened to
        -- start.
        checker: nsl_transceiver.prbs.prbs_checker
          generic map(
            byte_count_c => byte_count_c
            )
          port map(
            clock_i => word_clock_s,
            reset_n_i => lane_reset_n_s,

            mode_i => rx_s_i(lane_idx).prbs_select,
            restart_i => rx_s_i(lane_idx).prbs_error_reset,

            data_i => rx_data_s(0 to byte_count_c-1),
            valid_i => rx_valid_s,

            locked_o => locked_s,
            error_o => error_s,
            error_bit_count_o => open
            );

        rx_m_o(lane_idx).data <= (others => (others => '-'));
        rx_m_o(lane_idx).aux <= (others => (others => '-'));
        rx_m_o(lane_idx).valid <= '0';
        -- Word alignment means nothing to a pattern: there is no
        -- comma in it and nothing framed by one.
        rx_m_o(lane_idx).pcs_aligned <= '0';
        rx_m_o(lane_idx).clock_corrected <= '0';
        rx_m_o(lane_idx).status <= (others => '0');
        rx_m_o(lane_idx).prbs_locked <= locked_s;
        rx_m_o(lane_idx).prbs_error <= error_s;

      end generate;

      -- One word per lane clock either way, and the model always has
      -- room for it.
      tx_s_o(lane_idx).ready <= lane_reset_n_s;
      tx_s_o(lane_idx).pll_lock <= pll_locked_s(cfg_c.pll_index);
      tx_s_o(lane_idx).status <= (others => '0');

    end generate;

    disabled_lane: if not config_c.lanes(lane_idx).enabled generate
      lane_tx_o(lane_idx) <= nsl_io.diff.to_diff('0');
      lane_tx_clock_o(lane_idx) <= '0';
      lane_rx_clock_o(lane_idx) <= '0';
      tx_s_o(lane_idx) <= nsl_transceiver.lane.null_tx_slave_c;
      rx_m_o(lane_idx) <= nsl_transceiver.lane.null_rx_master_c;
    end generate;

  end generate;

end architecture;
