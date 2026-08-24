library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_inet.mac.all;
use nsl_inet.switching.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Stimulus and checkers around one switching_ingress instance.  The
-- entity plays the three peers of the block at once: the MAC feeding
-- the ingress stream, the shared MAC table answering lookups, and the
-- fabric pulling frames and acknowledging copies.
entity ingress_checker is
  generic(
    name_c: string;
    byte_count_c: natural range 1 to 4
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out std_ulogic
    );
end entity;

architecture beh of ingress_checker is

  constant port_count_c: natural := 8;
  constant port_index_c: port_index_t := 2;

  constant cfg_c: nsl_inet.switching.config_t
    := nsl_inet.switching.config(byte_count => byte_count_c,
                                 port_count => port_count_c,
                                 buffer_bytes_l2 => 11);

  constant pcfg_c: nsl_amba.axi4_stream.config_t := port_config(cfg_c);
  constant icfg_c: nsl_amba.axi4_stream.config_t := internal_config(cfg_c);

  function onehot(index: natural) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    ret(index) := '1';
    return ret;
  end function;

  -- Ports 0, 2 and 3 receive flooded traffic in the general case.
  constant flood_default_c: port_mask_t := "1011000000000000";
  -- Ingress port itself is always excluded from the flood set.
  constant flood_expect_c: port_mask_t := "1001000000000000";
  -- Flood set used by the replay scenario, so that a flooded frame
  -- has exactly three destinations.
  constant flood_mc_c: port_mask_t := "0110100100000000";
  constant mc_expect_c: port_mask_t := "0100100100000000";

  constant mac_a_c: mac48_t := from_hex("020000000001");
  constant mac_b_c: mac48_t := from_hex("020000000009");
  constant mac_hit_c: mac48_t := from_hex("0a0000000005");
  constant mac_self_c: mac48_t := from_hex("0a0000000002");
  constant mac_miss_c: mac48_t := from_hex("0a00000000fe");

  constant hit_mask_c: port_mask_t := onehot(5);

  constant order_hit_c: port_index_vector(0 to 0) := (0 => 5);
  constant order_flood_c: port_index_vector(0 to 1) := (0, 3);
  constant order_flood_rev_c: port_index_vector(0 to 1) := (3, 0);
  constant order_mc_c: port_index_vector(0 to 2) := (4, 1, 7);

  function make_frame(da, sa: mac48_t; length: natural) return byte_string
  is
    variable ret: byte_string(0 to length-1);
  begin
    ret(0 to 5) := da;
    ret(6 to 11) := sa;
    for i in 12 to length-1
    loop
      ret(i) := byte(to_unsigned((i * 7 + length) mod 256, 8));
    end loop;
    return ret;
  end function;

  constant f_hit_c: byte_string := make_frame(mac_hit_c, mac_a_c, 63);
  constant f_miss_c: byte_string := make_frame(mac_miss_c, mac_a_c, 62);
  constant f_bcast_c: byte_string := make_frame(ethernet_broadcast_addr_c, mac_a_c, 61);
  constant f_self_c: byte_string := make_frame(mac_self_c, mac_a_c, 60);
  constant f_bad_c: byte_string := make_frame(mac_hit_c, mac_b_c, 59);
  constant f_short_c: byte_string := make_frame(mac_hit_c, mac_b_c, 13);
  constant f_big0_c: byte_string := make_frame(mac_hit_c, mac_a_c, 600);
  constant f_big1_c: byte_string := make_frame(mac_hit_c, mac_a_c, 601);
  constant f_huge_c: byte_string := make_frame(mac_hit_c, mac_b_c, 1200);
  constant f_mc_c: byte_string := make_frame(ethernet_broadcast_addr_c, mac_a_c, 65);

  signal in_s, frame_s: bus_t;
  signal query_s: lookup_query_t;
  signal result_s: lookup_result_t;
  signal learn_s: learn_t;
  signal forward_req_s: forward_req_t;
  signal forward_ack_s: forward_ack_t;
  signal flood_s: port_mask_t;

  signal learn_count_s: natural;
  signal learn_mac_s: mac48_t;

  signal announce_count_s: natural;
  signal announce_prev_s: std_ulogic;

begin

  dut: nsl_inet.switching.switching_ingress
    generic map(
      config_c => cfg_c,
      port_index_c => port_index_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flood_mask_i => flood_s,

      in_i => in_s.m,
      in_o => in_s.s,

      lookup_query_o => query_s,
      lookup_result_i => result_s,
      learn_o => learn_s,

      frame_o => frame_s.m,
      frame_i => frame_s.s,
      forward_o => forward_req_s,
      forward_i => forward_ack_s
      );

  -- MAC table model.  Answers a query a few cycles after seeing it,
  -- with a single-cycle result pulse.
  table: process is
    variable mac_v: mac48_t;
  begin
    result_s.valid <= '0';
    result_s.hit <= '0';
    result_s.mask <= (others => '0');

    loop
      wait until rising_edge(clock_i);

      if query_s.valid = '1' then
        mac_v := query_s.mac;

        for i in 1 to 3
        loop
          wait until rising_edge(clock_i);
        end loop;
        wait until falling_edge(clock_i);

        result_s.valid <= '1';
        if mac_v = mac_hit_c then
          result_s.hit <= '1';
          result_s.mask <= hit_mask_c;
        elsif mac_v = mac_self_c then
          result_s.hit <= '1';
          result_s.mask <= onehot(port_index_c);
        else
          result_s.hit <= '0';
          result_s.mask <= (others => '-');
        end if;

        wait until rising_edge(clock_i);
        wait until falling_edge(clock_i);
        result_s.valid <= '0';
      end if;
    end loop;
  end process;

  learn_monitor: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if learn_s.valid = '1' then
        learn_count_s <= learn_count_s + 1;
        learn_mac_s <= learn_s.mac;
      end if;
    end if;

    if reset_n_i = '0' then
      learn_count_s <= 0;
      learn_mac_s <= (others => x"00");
    end if;
  end process;

  -- Counts head-of-queue announcements.  The pending mask stays
  -- asserted across the replays of one frame, so this rises once per
  -- frame that actually reaches the fabric.
  announce_monitor: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      announce_prev_s <= forward_req_s.valid;
      if forward_req_s.valid = '1' and announce_prev_s = '0' then
        announce_count_s <= announce_count_s + 1;
      end if;
    end if;

    if reset_n_i = '0' then
      announce_count_s <= 0;
      announce_prev_s <= '0';
    end if;
  end process;

  stim: process is

    variable announce_v: natural;

    procedure idle(constant cycles: natural) is
    begin
      for i in 1 to cycles
      loop
        wait until falling_edge(clock_i);
      end loop;
    end procedure;

    -- Drives one frame on the ingress stream.  The block may never
    -- backpressure, so beats go out one per cycle.
    procedure send_frame(constant data: byte_string;
                         constant bad: boolean) is
      variable offset_v, count_v: natural;
      variable data_v: byte_string(0 to byte_count_c-1);
      variable keep_v: std_ulogic_vector(0 to byte_count_c-1);
      variable user_v: std_ulogic_vector(0 downto 0);
      variable last_v: boolean;
    begin
      offset_v := 0;

      while offset_v < data'length
      loop
        count_v := data'length - offset_v;
        if count_v > byte_count_c then
          count_v := byte_count_c;
        end if;
        last_v := offset_v + count_v >= data'length;

        data_v := (others => x"00");
        keep_v := (others => '0');
        for i in 0 to count_v-1
        loop
          data_v(i) := data(data'low + offset_v + i);
          keep_v(i) := '1';
        end loop;

        if last_v and bad then
          user_v := "1";
        else
          user_v := "0";
        end if;

        in_s.m <= transfer(pcfg_c,
                           bytes => data_v,
                           keep => keep_v,
                           user => user_v,
                           last => last_v);

        wait until rising_edge(clock_i);
        assert in_s.s.ready = '1'
          report name_c&": ingress backpressured the MAC"
          severity failure;
        wait until falling_edge(clock_i);

        offset_v := offset_v + count_v;
      end loop;

      in_s.m <= transfer_defaults(pcfg_c);
    end procedure;

    procedure check_learn(constant count: natural;
                          constant mac: mac48_t) is
    begin
      idle(3);
      assert_equal(name_c, "learn count", learn_count_s, count, FAILURE);
      if count /= 0 then
        assert_equal(name_c, "learned address", learn_mac_s, mac, FAILURE);
      end if;
    end procedure;

    -- Pulls one frame from the fabric side, one copy per entry of
    -- order, checking the announced mask before every copy and the
    -- frame contents on every copy.
    -- early_ack acknowledges the copy on the very cycle its last beat
    -- is taken, stall exercises fabric backpressure in the middle of
    -- a copy.
    procedure expect_frame(constant data: byte_string;
                           constant mask: port_mask_t;
                           constant order: port_index_vector;
                           constant early_ack: boolean := false;
                           constant stall: boolean := false) is
      variable pending_v, taken_v: port_mask_t;
      variable offset_v, count_v: natural;
      variable data_v: byte_string(0 to byte_count_c-1);
      variable last_v, ready_v: boolean;
      variable guard_v: natural;
    begin
      pending_v := mask;

      for copy in order'range
      loop
        taken_v := (others => '0');
        taken_v(order(copy)) := '1';

        guard_v := 0;
        loop
          wait until rising_edge(clock_i);
          exit when forward_req_s.valid = '1';
          wait until falling_edge(clock_i);
          guard_v := guard_v + 1;
          assert guard_v < 20000
            report name_c&": no frame announced"
            severity failure;
        end loop;
        wait until falling_edge(clock_i);

        assert_equal(name_c, "announced mask", forward_req_s.mask, pending_v, FAILURE);

        offset_v := 0;
        last_v := false;
        ready_v := true;
        guard_v := 0;

        loop
          if stall then
            ready_v := not ready_v;
          end if;
          frame_s.s <= accept(icfg_c, ready_v);

          -- The buffer output is registered, so the beat visible now
          -- is the one that will be taken on the coming clock edge.
          if early_ack and ready_v and frame_s.m.valid = '1'
            and is_last(icfg_c, frame_s.m) then
            forward_ack_s.taken <= taken_v;
          end if;

          wait until rising_edge(clock_i);

          if ready_v and frame_s.m.valid = '1' then
            count_v := byte_count(icfg_c, frame_s.m);
            data_v := bytes(icfg_c, frame_s.m);
            last_v := is_last(icfg_c, frame_s.m);

            assert offset_v + count_v <= data'length
              report name_c&": frame is longer than expected"
              severity failure;

            for i in 0 to count_v-1
            loop
              assert_equal(name_c, "byte "&to_string(offset_v + i),
                           data_v(i), data(data'low + offset_v + i), FAILURE);
            end loop;

            offset_v := offset_v + count_v;

            if last_v then
              assert_equal(name_c, "last beat byte count", count_v,
                           ((data'length - 1) mod byte_count_c) + 1, FAILURE);
            end if;
          end if;

          wait until falling_edge(clock_i);
          exit when last_v;

          guard_v := guard_v + 1;
          assert guard_v < 20000
            report name_c&": frame never completed"
            severity failure;
        end loop;

        frame_s.s <= accept(icfg_c, false);
        assert_equal(name_c, "frame length", offset_v, data'length, FAILURE);

        if early_ack then
          forward_ack_s.taken <= (others => '0');
        else
          forward_ack_s.taken <= taken_v;
          wait until rising_edge(clock_i);
          wait until falling_edge(clock_i);
          forward_ack_s.taken <= (others => '0');
        end if;

        pending_v(order(copy)) := '0';
      end loop;

      wait until falling_edge(clock_i);
      assert forward_req_s.valid = '0'
        report name_c&": frame still announced after last copy"
        severity failure;
    end procedure;

  begin
    done_o <= '0';
    in_s.m <= transfer_defaults(pcfg_c);
    frame_s.s <= accept(icfg_c, false);
    forward_ack_s.taken <= (others => '0');
    flood_s <= flood_default_c;

    wait until reset_n_i = '1';
    idle(4);

    -- Unicast, known destination.
    send_frame(f_hit_c, false);
    check_learn(1, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);

    -- Unknown destination, flooded.
    send_frame(f_miss_c, false);
    check_learn(2, mac_a_c);
    expect_frame(f_miss_c, flood_expect_c, order_flood_c);

    -- Broadcast destination, flooded without consulting the table.
    send_frame(f_bcast_c, false);
    check_learn(3, mac_a_c);
    expect_frame(f_bcast_c, flood_expect_c, order_flood_rev_c, early_ack => true);

    -- Destination sits on the ingress port: frame is dropped, the
    -- source is still learned, and the next frame is unaffected.
    send_frame(f_self_c, false);
    check_learn(4, mac_a_c);
    send_frame(f_hit_c, false);
    check_learn(5, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);

    -- Bad frame: dropped, not learned from.
    send_frame(f_bad_c, true);
    check_learn(5, mac_a_c);
    send_frame(f_hit_c, false);
    check_learn(6, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);

    -- Runt frame: no complete header, dropped.
    send_frame(f_short_c, false);
    check_learn(6, mac_a_c);
    send_frame(f_hit_c, false);
    check_learn(7, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c, stall => true);

    -- Buffer overflow: the fabric side is held back while more than
    -- one buffer worth of frames is pushed in.  The frame that does
    -- not fit is dropped as a whole, those before it are intact.
    log_info(name_c, "overflow scenario");
    send_frame(f_big0_c, false);
    send_frame(f_big1_c, false);
    send_frame(f_huge_c, false);
    check_learn(9, mac_a_c);
    expect_frame(f_big0_c, hit_mask_c, order_hit_c);
    expect_frame(f_big1_c, hit_mask_c, order_hit_c);
    send_frame(f_hit_c, false);
    check_learn(10, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);

    -- Multicast replay: one copy per destination, acknowledged one at
    -- a time, out of order.
    log_info(name_c, "replay scenario");
    flood_s <= flood_mc_c;
    send_frame(f_mc_c, false);
    check_learn(11, mac_a_c);
    expect_frame(f_mc_c, mc_expect_c, order_mc_c, early_ack => true);
    flood_s <= flood_default_c;

    -- Buffer is free again after the last copy.
    send_frame(f_hit_c, false);
    check_learn(12, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);

    -- Empty egress mask right in front of a normal frame.  The first
    -- one has to be stepped over without ever being announced or read
    -- out, and must leave the one behind it intact.
    log_info(name_c, "skip scenario");
    announce_v := announce_count_s;
    send_frame(f_self_c, false);
    send_frame(f_hit_c, false);
    check_learn(14, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);
    assert_equal(name_c, "announcements across the skip",
                 announce_count_s - announce_v, 1, FAILURE);

    -- Buffer pointers came out of the skip consistent.
    send_frame(f_bcast_c, false);
    check_learn(15, mac_a_c);
    expect_frame(f_bcast_c, flood_expect_c, order_flood_c);

    -- Several frames piled up behind a fabric that takes none of
    -- them.  Their metadata has to come back in commit order, and the
    -- one with an empty mask has to disappear from the sequence
    -- without disturbing the frames on either side of it.
    log_info(name_c, "queue scenario");
    announce_v := announce_count_s;
    send_frame(f_hit_c, false);
    send_frame(f_miss_c, false);
    send_frame(f_bcast_c, false);
    send_frame(f_self_c, false);
    send_frame(f_mc_c, false);
    check_learn(20, mac_a_c);
    expect_frame(f_hit_c, hit_mask_c, order_hit_c);
    -- Backpressure across a replay: the fabric is still draining the
    -- tail of a copy while the copy is already waiting to be
    -- acknowledged, and the rewind that follows must not start on it.
    expect_frame(f_miss_c, flood_expect_c, order_flood_c, stall => true);
    expect_frame(f_bcast_c, flood_expect_c, order_flood_rev_c);
    expect_frame(f_mc_c, flood_expect_c, order_flood_c);
    assert_equal(name_c, "announcements across the queue",
                 announce_count_s - announce_v, 4, FAILURE);

    log_info(name_c, "all scenarios passed");

    done_o <= '1';
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

begin

  byte: entity work.ingress_checker
    generic map(
      name_c => "ingress 1B",
      byte_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  half_word: entity work.ingress_checker
    generic map(
      name_c => "ingress 2B",
      byte_count_c => 2
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  word: entity work.ingress_checker
    generic map(
      name_c => "ingress 4B",
      byte_count_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

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
