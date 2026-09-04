library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_amba, nsl_data, nsl_logic, nsl_mii, nsl_simulation, nsl_time;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_mii.flit.all;
use nsl_mii.mii.all;
use nsl_mii.timestamping.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_time.timestamp.all;

architecture arch of tb is

  constant cfg_c: config_t := axi4_flit_cfg;
  constant id_bits_c: natural := 2;
  constant id_count_c: natural := 2 ** id_bits_c;

  -- Frames of the receive scenarios: the first ones with an idle
  -- consumer, the last ones with a stalling one.
  constant rx_frame_count_c: natural := 12;
  constant rx_smooth_count_c: natural := 6;

  -- Frames of the loopback scenario.
  constant loop_frame_count_c: natural := 4;
  constant loop_frame_size_c: natural := 60;

  -- Frames of the multi-domain scenario.
  constant md_frame_count_c: natural := 8;

  -- Latency of the sideband crossing, counted from the core clock
  -- edge that samples the tagger sideband to the far-side edge that
  -- writes the capture register:
  --  1 core cycle for the crossing to take the word,
  --  up to 1 far cycle for the toggle to meet a far clock edge,
  --  2 far cycles of resynchronizer,
  --  1 far cycle for the crossing output side to publish the word,
  --  1 far cycle for the strobe register.
  -- Against the reference the generator samples half a core cycle
  -- after the strobe, with 8 ns core and 7 ns rtc clocks, that lands
  -- on 5 or 6 rtc cycles.  One cycle of margin each way keeps the
  -- bound from depending on which of the two lands.
  constant md_rtc_latency_min_c: natural := 4;
  constant md_rtc_latency_max_c: natural := 7;

  -- Same path with both clocks tied together: the far cycles above
  -- are core cycles, and the toggle alignment costs a full cycle
  -- since a signal launched on an edge is only seen on the next one.
  constant md_deg_latency_c: natural := 6;

  type tag_id_vector is array(natural range <>) of tag_id_t;
  type timestamp_vector is array(natural range <>) of timestamp_t;

  type tx_test_t is
  record
    strobes: boolean;
    id: tag_id_t;
    size: natural;
  end record;

  type tx_test_vector is array(natural range <>) of tx_test_t;

  constant tx_tests_c: tx_test_vector(0 to 7) := (
    (strobes => true, id => x"3", size => 4),
    (strobes => false, id => x"5", size => 9),
    (strobes => true, id => x"c", size => 1),
    (strobes => false, id => x"0", size => 6),
    (strobes => true, id => x"7", size => 3),
    (strobes => true, id => x"1", size => 12),
    (strobes => false, id => x"f", size => 2),
    (strobes => true, id => x"a", size => 5)
    );

  constant loop_ids_c: tag_id_vector(0 to loop_frame_count_c-1)
    := (x"5", x"3", x"9", x"e");

  signal clock_s, mii_clock_s, rtc_clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 9);

  -- Free-running time base the capture register file samples.
  signal timestamp_s: timestamp_t;

  -- Time base of the rtc domain.  It counts its own cycles, so
  -- differences read directly as a count of rtc cycles.
  signal rtc_timestamp_s: timestamp_t;

  signal rx_sfd_s, rx_tagger_sfd_s: std_ulogic;
  signal rx_tagger_id_s: tag_id_t;
  signal rx_in_s, rx_out_s: bus_t;
  signal read_id_s: unsigned(3 downto 0);
  signal read_timestamp_s: timestamp_t;
  signal rx_expected_ts_s: timestamp_vector(0 to rx_frame_count_c-1);

  signal tx_sfd_s, tx_strobe_s: std_ulogic;
  signal tx_id_s: tag_id_t;
  signal tx_in_s, tx_out_s: bus_t;
  signal tx_strobe_log_s: tag_id_vector(0 to 31);
  signal tx_strobe_count_s: natural;

  signal mii_s: mii_io;
  signal loop_tx_in_s, loop_tx_mid_s, loop_rx_raw_s, loop_rx_out_s: bus_t;
  signal loop_tx_sfd_s, loop_rx_sfd_s: std_ulogic;
  signal loop_strobe_s: std_ulogic;
  signal loop_id_s: tag_id_t;
  signal loop_strobe_log_s: tag_id_vector(0 to 31);
  signal loop_strobe_count_s: natural;

  signal md_sfd_s, md_tagger_sfd_s: std_ulogic;
  signal md_tagger_id_s: tag_id_t;
  signal md_in_s, md_out_s: bus_t;

  -- Time bases sampled by the generator when it launches an event.
  signal md_launch_rtc_s: timestamp_vector(0 to md_frame_count_c-1);
  signal md_launch_ts_s: timestamp_vector(0 to md_frame_count_c-1);

  -- Crossing into the rtc domain, and what the rtc side saw.
  signal md_rtc_strobe_s, md_rtc_done_s: std_ulogic;
  signal md_rtc_id_s: tag_id_t;
  signal md_rtc_read_id_s: unsigned(3 downto 0);
  signal md_rtc_read_ts_s: timestamp_t;
  signal md_rtc_log_id_s: tag_id_vector(0 to 2*md_frame_count_c-1);
  signal md_rtc_log_ts_s: timestamp_vector(0 to 2*md_frame_count_c-1);
  signal md_rtc_log_count_s, md_rtc_done_count_s: natural;

  -- Same crossing with both clocks tied together.
  signal md_deg_strobe_s, md_deg_done_s: std_ulogic;
  signal md_deg_id_s: tag_id_t;
  signal md_deg_read_id_s: unsigned(3 downto 0);
  signal md_deg_read_ts_s: timestamp_t;
  signal md_deg_log_id_s: tag_id_vector(0 to 2*md_frame_count_c-1);
  signal md_deg_log_ts_s: timestamp_vector(0 to 2*md_frame_count_c-1);
  signal md_deg_log_count_s, md_deg_done_count_s: natural;

  -- Payload bytes of a frame, distinct for every index.
  function frame_of(index: natural; size: natural) return byte_string
  is
    variable ret: byte_string(0 to size-1);
  begin
    for i in ret'range
    loop
      ret(i) := std_ulogic_vector(to_unsigned((index * 53 + i * 7 + 1) mod 256, 8));
    end loop;
    return ret;
  end function;

  procedure wait_cycles(signal clock: in std_ulogic;
                        constant count: natural)
  is
  begin
    for i in 1 to count
    loop
      wait until falling_edge(clock);
    end loop;
  end procedure;

  -- Pulses the strobe for one cycle and returns the time base value
  -- the capture register file takes: the sideband of the tagger is
  -- registered, so the capture happens the cycle after the strobe.
  procedure sfd_pulse(signal clock: in std_ulogic;
                      signal timestamp: in timestamp_t;
                      signal sfd: out std_ulogic;
                      variable captured: out timestamp_t)
  is
  begin
    sfd <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    sfd <= '0';
    captured := timestamp;
    wait until falling_edge(clock);
  end procedure;

  procedure sfd_pulse(signal clock: in std_ulogic;
                      signal sfd: out std_ulogic)
  is
  begin
    sfd <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    sfd <= '0';
    wait until falling_edge(clock);
  end procedure;

  procedure packet_put(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal stream_i: in slave_t;
                       signal stream_o: out master_t;
                       constant data: byte_string;
                       variable seed1: inout positive;
                       variable seed2: inout positive;
                       constant idle_prob: real)
  is
    alias d: byte_string(0 to data'length-1) is data;
    variable rand_v: real;
  begin
    for i in d'range
    loop
      uniform(seed1, seed2, rand_v);
      if rand_v < idle_prob then
        wait until falling_edge(clock);
      end if;

      send(cfg, clock, stream_i, stream_o,
           bytes => from_suv(d(i)),
           user => "0",
           last => i = d'high);
    end loop;
  end procedure;

  procedure packet_get(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal stream_i: in master_t;
                       signal stream_o: out slave_t;
                       variable packet: inout byte_stream;
                       variable seed1: inout positive;
                       variable seed2: inout positive;
                       constant stall_prob: real)
  is
    variable rand_v: real;
    variable ready_v, done_v: boolean;
  begin
    clear(packet);
    done_v := false;

    while not done_v
    loop
      uniform(seed1, seed2, rand_v);
      ready_v := rand_v >= stall_prob;
      stream_o <= accept(cfg, ready_v);

      wait until rising_edge(clock);
      if ready_v and is_valid(cfg, stream_i) then
        write(packet, bytes(cfg, stream_i)(0));
        done_v := is_last(cfg, stream_i);
      end if;

      wait until falling_edge(clock);
    end loop;

    stream_o <= accept(cfg, false);
  end procedure;

begin

  time_base: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      timestamp_s.nanosecond <= timestamp_s.nanosecond + 8;
    end if;

    if reset_n_s = '0' then
      timestamp_s <= timestamp_zero_c;
    end if;
  end process;

  -- Part 1: receive tagger driven by a fake layer-1 driver.

  rx_gen: process is
    variable seed1_v: positive := 17;
    variable seed2_v: positive := 41;
    variable ts_v: timestamp_t;
  begin
    done_s(0) <= '0';
    rx_in_s.m <= transfer_defaults(cfg_c);
    rx_sfd_s <= '0';

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    -- Two strobes pending before the first frame emerges, then two
    -- frames back to back.
    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(0) <= ts_v;
    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(1) <= ts_v;
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(0, 5), seed1_v, seed2_v, 0.0);
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(1, 12), seed1_v, seed2_v, 0.0);

    -- One strobe leading its frame by a few cycles.
    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(2) <= ts_v;
    wait_cycles(clock_s, 7);
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(2, 1), seed1_v, seed2_v, 0.0);

    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(3) <= ts_v;
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(3, 3), seed1_v, seed2_v, 0.0);

    -- Identifier wrap-around, two more frames back to back.
    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(4) <= ts_v;
    sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
    rx_expected_ts_s(5) <= ts_v;
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(4, 8), seed1_v, seed2_v, 0.0);
    packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
               frame_of(5, 2), seed1_v, seed2_v, 0.0);

    -- Same again, with a stalling consumer and a bursty producer.
    for index in rx_smooth_count_c to rx_frame_count_c-1
    loop
      sfd_pulse(clock_s, timestamp_s, rx_sfd_s, ts_v);
      rx_expected_ts_s(index) <= ts_v;
      packet_put(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
                 frame_of(index, 4 + index), seed1_v, seed2_v, 0.3);
    end loop;

    done_s(0) <= '1';
    wait;
  end process;

  rx_chk: process is
    variable seed1_v: positive := 5501;
    variable seed2_v: positive := 991;
    variable data_v: byte_stream;
    variable expected_v: byte_stream;
    variable stall_v: real;
  begin
    done_s(1) <= '0';
    rx_out_s.s <= accept(cfg_c, false);
    read_id_s <= (others => '0');

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for index in 0 to rx_frame_count_c-1
    loop
      if index < rx_smooth_count_c then
        stall_v := 0.0;
      else
        stall_v := 0.4;
      end if;

      packet_get(cfg_c, clock_s, rx_out_s.m, rx_out_s.s,
                 data_v, seed1_v, seed2_v, stall_v);

      clear(expected_v);
      if index < rx_smooth_count_c then
        case index is
          when 0 => write(expected_v, frame_of(0, 5));
          when 1 => write(expected_v, frame_of(1, 12));
          when 2 => write(expected_v, frame_of(2, 1));
          when 3 => write(expected_v, frame_of(3, 3));
          when 4 => write(expected_v, frame_of(4, 8));
          when others => write(expected_v, frame_of(5, 2));
        end case;
      else
        write(expected_v, frame_of(index, 4 + index));
      end if;

      assert data_v.all'length = expected_v.all'length + tag_length_c
        report "Frame "&to_string(index)&" has "
        &to_string(data_v.all'length)&" bytes, expected "
        &to_string(expected_v.all'length + tag_length_c)
        severity failure;

      assert_equal("rx frame "&to_string(index)&" tag id",
                   std_ulogic_vector(tag_id(data_v.all(0))),
                   std_ulogic_vector(to_unsigned(index mod id_count_c, 4)),
                   failure);
      assert not tag_strobes(data_v.all(0))
        report "Frame "&to_string(index)&" tag requests a transmit strobe"
        severity failure;
      assert_equal("rx frame "&to_string(index)&" payload",
                   data_v.all(tag_length_c to data_v.all'length-1),
                   expected_v.all,
                   failure);

      read_id_s <= tag_id(data_v.all(0));
      wait for 1 ns;
      assert_equal("rx frame "&to_string(index)&" timestamp",
                   read_timestamp_s.nanosecond,
                   rx_expected_ts_s(index).nanosecond,
                   failure);
    end loop;

    log_info("Receive tagger scenarios passed");

    done_s(1) <= '1';
    wait;
  end process;

  rx_tagger: nsl_mii.timestamping.timestamping_rx_tagger
    generic map(
      config_c => cfg_c,
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sfd_i => rx_sfd_s,

      sfd_o => rx_tagger_sfd_s,
      id_o => rx_tagger_id_s,

      in_i => rx_in_s.m,
      in_o => rx_in_s.s,

      out_o => rx_out_s.m,
      out_i => rx_out_s.s
      );

  capture: nsl_time.capture.timestamp_capture
    generic map(
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      timestamp_i => timestamp_s,
      strobe_i => rx_tagger_sfd_s,
      id_i => rx_tagger_id_s,

      read_id_i => read_id_s,
      read_timestamp_o => read_timestamp_s
      );

  -- Part 1: transmit strober driven by a fake layer-1 driver.

  tx_gen: process is
    variable seed1_v: positive := 313;
    variable seed2_v: positive := 27;
    variable expected_v: natural;
  begin
    done_s(2) <= '0';
    tx_in_s.m <= transfer_defaults(cfg_c);
    tx_sfd_s <= '0';

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    -- More than one frame handed over before the first SFD strobes.
    for index in 0 to 3
    loop
      packet_put(cfg_c, clock_s, tx_in_s.s, tx_in_s.m,
                 tag_build(tx_tests_c(index).strobes, tx_tests_c(index).id)
                 & frame_of(index, tx_tests_c(index).size),
                 seed1_v, seed2_v, 0.0);
    end loop;

    for index in 0 to 3
    loop
      wait_cycles(clock_s, index * 3);
      sfd_pulse(clock_s, tx_sfd_s);
    end loop;

    -- One frame at a time, with the strobe trailing it.
    for index in 4 to tx_tests_c'high
    loop
      packet_put(cfg_c, clock_s, tx_in_s.s, tx_in_s.m,
                 tag_build(tx_tests_c(index).strobes, tx_tests_c(index).id)
                 & frame_of(index, tx_tests_c(index).size),
                 seed1_v, seed2_v, 0.2);
      wait_cycles(clock_s, index);
      sfd_pulse(clock_s, tx_sfd_s);
    end loop;

    wait_cycles(clock_s, 16);

    expected_v := 0;
    for index in tx_tests_c'range
    loop
      if tx_tests_c(index).strobes then
        assert_equal("tx strobe "&to_string(expected_v)&" id",
                     std_ulogic_vector(tx_strobe_log_s(expected_v)),
                     std_ulogic_vector(tx_tests_c(index).id),
                     failure);
        expected_v := expected_v + 1;
      end if;
    end loop;

    assert_equal("tx strobe count", tx_strobe_count_s, expected_v, failure);
    log_info("Transmit strober scenarios passed");

    done_s(2) <= '1';
    wait;
  end process;

  tx_chk: process is
    variable seed1_v: positive := 7717;
    variable seed2_v: positive := 131;
    variable data_v: byte_stream;
    variable stall_v: real;
  begin
    done_s(3) <= '0';
    tx_out_s.s <= accept(cfg_c, false);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for index in tx_tests_c'range
    loop
      if index < 4 then
        stall_v := 0.0;
      else
        stall_v := 0.35;
      end if;

      packet_get(cfg_c, clock_s, tx_out_s.m, tx_out_s.s,
                 data_v, seed1_v, seed2_v, stall_v);

      assert_equal("tx frame "&to_string(index),
                   data_v.all,
                   frame_of(index, tx_tests_c(index).size),
                   failure);
    end loop;

    done_s(3) <= '1';
    wait;
  end process;

  tx_strobe_watch: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if tx_strobe_s = '1' and tx_strobe_count_s <= tx_strobe_log_s'high then
        tx_strobe_log_s(tx_strobe_count_s) <= tx_id_s;
        tx_strobe_count_s <= tx_strobe_count_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      tx_strobe_count_s <= 0;
    end if;
  end process;

  tx_strober: nsl_mii.timestamping.timestamping_tx_strober
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sfd_i => tx_sfd_s,

      strobe_o => tx_strobe_s,
      id_o => tx_id_s,

      in_i => tx_in_s.m,
      in_o => tx_in_s.s,

      out_o => tx_out_s.m,
      out_i => tx_out_s.s
      );

  -- Part 2: both shims around a MII driver looped back on itself.

  loop_gen: process is
    variable seed1_v: positive := 65;
    variable seed2_v: positive := 4001;
  begin
    done_s(4) <= '0';
    loop_tx_in_s.m <= transfer_defaults(cfg_c);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for index in 0 to loop_frame_count_c-1
    loop
      packet_put(cfg_c, clock_s, loop_tx_in_s.s, loop_tx_in_s.m,
                 tag_build(true, loop_ids_c(index))
                 & frame_of(index, loop_frame_size_c),
                 seed1_v, seed2_v, 0.0);
    end loop;

    for i in 1 to 40000
    loop
      exit when loop_strobe_count_s = loop_frame_count_c;
      wait until falling_edge(clock_s);
    end loop;

    assert_equal("loopback strobe count",
                 loop_strobe_count_s, loop_frame_count_c, failure);

    for index in 0 to loop_frame_count_c-1
    loop
      assert_equal("loopback strobe "&to_string(index)&" id",
                   std_ulogic_vector(loop_strobe_log_s(index)),
                   std_ulogic_vector(loop_ids_c(index)),
                   failure);
    end loop;

    log_info("Loopback transmit strobes passed");

    done_s(4) <= '1';
    wait;
  end process;

  loop_chk: process is
    variable seed1_v: positive := 887;
    variable seed2_v: positive := 3;
    variable data_v: byte_stream;
  begin
    done_s(5) <= '0';
    loop_rx_out_s.s <= accept(cfg_c, false);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for index in 0 to loop_frame_count_c-1
    loop
      packet_get(cfg_c, clock_s, loop_rx_out_s.m, loop_rx_out_s.s,
                 data_v, seed1_v, seed2_v, 0.0);

      assert data_v.all'length = loop_frame_size_c + tag_length_c
        report "Loopback frame "&to_string(index)&" has "
        &to_string(data_v.all'length)&" bytes"
        severity failure;

      assert_equal("loopback frame "&to_string(index)&" tag id",
                   std_ulogic_vector(tag_id(data_v.all(0))),
                   std_ulogic_vector(to_unsigned(index mod id_count_c, 4)),
                   failure);
      assert_equal("loopback frame "&to_string(index)&" payload",
                   data_v.all(tag_length_c to data_v.all'length-1),
                   frame_of(index, loop_frame_size_c),
                   failure);
    end loop;

    log_info("Loopback receive tags passed");

    done_s(5) <= '1';
    wait;
  end process;

  loop_strobe_watch: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if loop_strobe_s = '1' and loop_strobe_count_s <= loop_strobe_log_s'high then
        loop_strobe_log_s(loop_strobe_count_s) <= loop_id_s;
        loop_strobe_count_s <= loop_strobe_count_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      loop_strobe_count_s <= 0;
    end if;
  end process;

  loop_strober: nsl_mii.timestamping.timestamping_tx_strober
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sfd_i => loop_tx_sfd_s,

      strobe_o => loop_strobe_s,
      id_o => loop_id_s,

      in_i => loop_tx_in_s.m,
      in_o => loop_tx_in_s.s,

      out_o => loop_tx_mid_s.m,
      out_i => loop_tx_mid_s.s
      );

  loop_driver: nsl_mii.mii.mii_axi_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      rx_sfd_o => loop_rx_sfd_s,
      tx_sfd_o => loop_tx_sfd_s,

      mii_o => mii_s.m2p,
      mii_i => mii_s.p2m,

      rx_o => loop_rx_raw_s.m,
      rx_i => loop_rx_raw_s.s,

      tx_i => loop_tx_mid_s.m,
      tx_o => loop_tx_mid_s.s
      );

  -- The Phy end of the link, wired back on itself.  Receive signals
  -- are sampled half a period away from the edge that drives the
  -- transmit ones.
  mii_s.p2m.rx.clk <= not mii_clock_s;
  mii_s.p2m.rx.d <= mii_s.m2p.tx.d;
  mii_s.p2m.rx.dv <= mii_s.m2p.tx.en;
  mii_s.p2m.rx.er <= mii_s.m2p.tx.er;
  mii_s.p2m.tx.clk <= mii_clock_s;
  mii_s.p2m.status.crs <= '0';
  mii_s.p2m.status.col <= '0';

  loop_tagger: nsl_mii.timestamping.timestamping_rx_tagger
    generic map(
      config_c => cfg_c,
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sfd_i => loop_rx_sfd_s,

      sfd_o => open,
      id_o => open,

      in_i => loop_rx_raw_s.m,
      in_o => loop_rx_raw_s.s,

      out_o => loop_rx_out_s.m,
      out_i => loop_rx_out_s.s
      );

  -- Part 3: receive sideband crossed into a time base of its own.

  rtc_time_base: process(rtc_clock_s, reset_n_s) is
  begin
    if rising_edge(rtc_clock_s) then
      rtc_timestamp_s.nanosecond <= rtc_timestamp_s.nanosecond + 1;
    end if;

    if reset_n_s = '0' then
      rtc_timestamp_s <= timestamp_zero_c;
    end if;
  end process;

  md_gen: process is
    variable seed1_v: positive := 991;
    variable seed2_v: positive := 77;
  begin
    done_s(6) <= '0';
    md_in_s.m <= transfer_defaults(cfg_c);
    md_sfd_s <= '0';

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);
    -- The crossing resynchronizes the reset into both domains, and
    -- drops events launched before that release reaches them.
    wait_cycles(clock_s, 16);

    for index in 0 to md_frame_count_c-1
    loop
      md_sfd_s <= '1';
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
      md_sfd_s <= '0';
      md_launch_rtc_s(index) <= rtc_timestamp_s;
      md_launch_ts_s(index) <= timestamp_s;
      wait until falling_edge(clock_s);

      packet_put(cfg_c, clock_s, md_in_s.s, md_in_s.m,
                 frame_of(index, 3 + index), seed1_v, seed2_v, 0.2);

      -- A crossing carries one event at a time, so the earliest
      -- legal next strobe is the one that follows this event's
      -- completion on both crossings.
      while md_rtc_done_count_s <= index or md_deg_done_count_s <= index
      loop
        wait until falling_edge(clock_s);
      end loop;

      -- Half the rounds keep that minimum spacing, the others let
      -- the sideband idle for a while.
      if index mod 2 = 0 then
        wait_cycles(clock_s, 5 + index);
      end if;
    end loop;

    done_s(6) <= '1';
    wait;
  end process;

  md_sink: process is
    variable seed1_v: positive := 4243;
    variable seed2_v: positive := 17;
    variable data_v: byte_stream;
  begin
    done_s(7) <= '0';
    md_out_s.s <= accept(cfg_c, false);

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for index in 0 to md_frame_count_c-1
    loop
      packet_get(cfg_c, clock_s, md_out_s.m, md_out_s.s,
                 data_v, seed1_v, seed2_v, 0.25);

      assert data_v.all'length = 3 + index + tag_length_c
        report "Multi-domain frame "&to_string(index)&" has "
        &to_string(data_v.all'length)&" bytes"
        severity failure;

      assert_equal("md frame "&to_string(index)&" tag id",
                   std_ulogic_vector(tag_id(data_v.all(0))),
                   std_ulogic_vector(to_unsigned(index mod id_count_c, 4)),
                   failure);
      assert_equal("md frame "&to_string(index)&" payload",
                   data_v.all(tag_length_c to data_v.all'length-1),
                   frame_of(index, 3 + index),
                   failure);
    end loop;

    done_s(7) <= '1';
    wait;
  end process;

  -- Reading the time base on the edge that sees the strobe yields the
  -- value the capture register file writes on that very edge.
  md_rtc_watch: process(rtc_clock_s, reset_n_s) is
  begin
    if rising_edge(rtc_clock_s) then
      if md_rtc_strobe_s = '1' and md_rtc_log_count_s <= md_rtc_log_id_s'high then
        md_rtc_log_id_s(md_rtc_log_count_s) <= md_rtc_id_s;
        md_rtc_log_ts_s(md_rtc_log_count_s) <= rtc_timestamp_s;
        md_rtc_log_count_s <= md_rtc_log_count_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      md_rtc_log_count_s <= 0;
    end if;
  end process;

  md_deg_watch: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if md_deg_strobe_s = '1' and md_deg_log_count_s <= md_deg_log_id_s'high then
        md_deg_log_id_s(md_deg_log_count_s) <= md_deg_id_s;
        md_deg_log_ts_s(md_deg_log_count_s) <= timestamp_s;
        md_deg_log_count_s <= md_deg_log_count_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      md_deg_log_count_s <= 0;
    end if;
  end process;

  md_done_watch: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if md_rtc_done_s = '1' then
        md_rtc_done_count_s <= md_rtc_done_count_s + 1;
      end if;
      if md_deg_done_s = '1' then
        md_deg_done_count_s <= md_deg_done_count_s + 1;
      end if;
    end if;

    if reset_n_s = '0' then
      md_rtc_done_count_s <= 0;
      md_deg_done_count_s <= 0;
    end if;
  end process;

  md_rtc_chk: process is
    variable delta_v, min_v, max_v: integer;
  begin
    done_s(8) <= '0';
    md_rtc_read_id_s <= (others => '0');
    min_v := integer'high;
    max_v := integer'low;

    wait until reset_n_s = '1';

    for index in 0 to md_frame_count_c-1
    loop
      -- done_o is registered, so the edge that reads it asserted is
      -- the earliest one a consumer could act on.
      wait until rising_edge(clock_s) and md_rtc_done_s = '1';

      assert_equal("md rtc strobe count at done "&to_string(index),
                   md_rtc_log_count_s, index + 1, failure);
      assert_equal("md rtc event "&to_string(index)&" id",
                   std_ulogic_vector(md_rtc_log_id_s(index)),
                   std_ulogic_vector(to_unsigned(index mod id_count_c, 4)),
                   failure);

      -- Read the rtc-domain register from the core domain with no
      -- synchronization, as a consumer trusting done_o would.
      md_rtc_read_id_s <= md_rtc_log_id_s(index);
      wait for 1 ns;
      assert_equal("md rtc event "&to_string(index)&" register",
                   md_rtc_read_ts_s.nanosecond,
                   md_rtc_log_ts_s(index).nanosecond,
                   failure);

      delta_v := to_integer(md_rtc_log_ts_s(index).nanosecond
                            - md_launch_rtc_s(index).nanosecond);
      assert delta_v >= md_rtc_latency_min_c
        and delta_v <= md_rtc_latency_max_c
        report "md rtc event "&to_string(index)&" captured "
        &to_string(delta_v)&" rtc cycles after the strobe"
        severity failure;

      if delta_v < min_v then
        min_v := delta_v;
      end if;
      if delta_v > max_v then
        max_v := delta_v;
      end if;
    end loop;

    wait_cycles(clock_s, 32);

    assert_equal("md rtc strobe count",
                 md_rtc_log_count_s, md_frame_count_c, failure);
    assert_equal("md rtc done count",
                 md_rtc_done_count_s, md_frame_count_c, failure);

    log_info("Multi-domain sideband crossing passed, capture "
             &to_string(min_v)&" to "&to_string(max_v)
             &" rtc cycles after the strobe");

    done_s(8) <= '1';
    wait;
  end process;

  md_deg_chk: process is
  begin
    done_s(9) <= '0';
    md_deg_read_id_s <= (others => '0');

    wait until reset_n_s = '1';

    for index in 0 to md_frame_count_c-1
    loop
      wait until rising_edge(clock_s) and md_deg_done_s = '1';

      assert_equal("md degenerate strobe count at done "&to_string(index),
                   md_deg_log_count_s, index + 1, failure);
      assert_equal("md degenerate event "&to_string(index)&" id",
                   std_ulogic_vector(md_deg_log_id_s(index)),
                   std_ulogic_vector(to_unsigned(index mod id_count_c, 4)),
                   failure);

      md_deg_read_id_s <= md_deg_log_id_s(index);
      wait for 1 ns;
      assert_equal("md degenerate event "&to_string(index)&" register",
                   md_deg_read_ts_s.nanosecond,
                   md_deg_log_ts_s(index).nanosecond,
                   failure);

      -- Single domain: the latency is exact.  The core time base
      -- steps by 8 every cycle.
      assert_equal("md degenerate event "&to_string(index)&" latency",
                   to_integer(md_deg_log_ts_s(index).nanosecond
                              - md_launch_ts_s(index).nanosecond),
                   md_deg_latency_c * 8, failure);
    end loop;

    wait_cycles(clock_s, 32);

    assert_equal("md degenerate strobe count",
                 md_deg_log_count_s, md_frame_count_c, failure);
    assert_equal("md degenerate done count",
                 md_deg_done_count_s, md_frame_count_c, failure);

    log_info("Single-clock sideband crossing passed");

    done_s(9) <= '1';
    wait;
  end process;

  md_tagger: nsl_mii.timestamping.timestamping_rx_tagger
    generic map(
      config_c => cfg_c,
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sfd_i => md_sfd_s,

      sfd_o => md_tagger_sfd_s,
      id_o => md_tagger_id_s,

      in_i => md_in_s.m,
      in_o => md_in_s.s,

      out_o => md_out_s.m,
      out_i => md_out_s.s
      );

  md_rtc_resync: nsl_mii.timestamping.timestamping_sideband_resync
    port map(
      reset_n_i => reset_n_s,

      a_clock_i => clock_s,
      a_strobe_i => md_tagger_sfd_s,
      a_id_i => md_tagger_id_s,
      a_done_o => md_rtc_done_s,

      b_clock_i => rtc_clock_s,
      b_strobe_o => md_rtc_strobe_s,
      b_id_o => md_rtc_id_s
      );

  md_rtc_capture: nsl_time.capture.timestamp_capture
    generic map(
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => rtc_clock_s,
      reset_n_i => reset_n_s,

      timestamp_i => rtc_timestamp_s,
      strobe_i => md_rtc_strobe_s,
      id_i => md_rtc_id_s,

      read_id_i => md_rtc_read_id_s,
      read_timestamp_o => md_rtc_read_ts_s
      );

  md_deg_resync: nsl_mii.timestamping.timestamping_sideband_resync
    port map(
      reset_n_i => reset_n_s,

      a_clock_i => clock_s,
      a_strobe_i => md_tagger_sfd_s,
      a_id_i => md_tagger_id_s,
      a_done_o => md_deg_done_s,

      b_clock_i => clock_s,
      b_strobe_o => md_deg_strobe_s,
      b_id_o => md_deg_id_s
      );

  md_deg_capture: nsl_time.capture.timestamp_capture
    generic map(
      id_bits_c => id_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      timestamp_i => timestamp_s,
      strobe_i => md_deg_strobe_s,
      id_i => md_deg_id_s,

      read_id_i => md_deg_read_id_s,
      read_timestamp_o => md_deg_read_ts_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 3,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      clock_period(1) => 40 ns,
      clock_period(2) => 7 ns,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => mii_clock_s,
      clock_o(2) => rtc_clock_s,
      done_i => done_s
      );

end;
