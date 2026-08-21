library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_inet, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_inet.ethernet.all;
use nsl_inet.switching.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Four switching_mac_table instances, each with its own stimulus
-- process:
--
-- * a plain learning table, for miss before learning, learning,
--   station move, concurrent queries and group address filtering,
-- * a single-bucket learning table, where filling the ways is enough
--   to force an eviction,
-- * a learning table with aging enabled, short enough to watch an
--   entry expire,
-- * a static table.
entity tb is
end tb;

architecture arch of tb is

  constant port_count_c: natural := 4;

  type bool_vector is array(natural range <>) of boolean;
  type mask_vector is array(natural range <>) of port_mask_t;

  constant learn_config_c: config_t := config(
    byte_count => 1,
    port_count => port_count_c,
    buffer_bytes_l2 => 11,
    table_entry_count_l2 => 4,
    table_way_count => 2,
    learning_enabled => true,
    age_time_l2 => 0
    );

  -- One bucket, two ways: the third address learned has to evict.
  constant evict_config_c: config_t := config(
    byte_count => 1,
    port_count => port_count_c,
    buffer_bytes_l2 => 11,
    table_entry_count_l2 => 0,
    table_way_count => 2,
    learning_enabled => true,
    age_time_l2 => 0
    );

  -- 16 buckets swept in 2**8 cycles, so an entry lives between 256 and
  -- 512 cycles.
  constant age_config_c: config_t := config(
    byte_count => 1,
    port_count => port_count_c,
    buffer_bytes_l2 => 11,
    table_entry_count_l2 => 4,
    table_way_count => 2,
    learning_enabled => true,
    age_time_l2 => 8
    );
  constant age_nominal_c: natural := 256;

  constant static_config_c: config_t := config(
    byte_count => 1,
    port_count => port_count_c,
    buffer_bytes_l2 => 11,
    table_entry_count_l2 => 4,
    table_way_count => 2,
    learning_enabled => false,
    age_time_l2 => 0
    );

  constant mac_a_c: mac48_t := from_hex("0200deadbe01");
  constant mac_b_c: mac48_t := from_hex("0200deadbe02");
  constant mac_c_c: mac48_t := from_hex("0200deadbe03");
  constant mac_d_c: mac48_t := from_hex("0200deadbe04");
  constant mac_unknown_c: mac48_t := from_hex("0201cafe0099");
  constant mac_group_c: mac48_t := from_hex("0180c2000001");

  constant static_macs_c: mac48_vector(0 to 2) := (mac_a_c, mac_b_c, mac_c_c);
  constant static_ports_c: port_index_vector(0 to 2) := (1, 3, 0);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 3);

  signal learn_query_s, evict_query_s, age_query_s, static_query_s:
    lookup_query_vector(0 to port_count_c-1);
  signal learn_result_s, evict_result_s, age_result_s, static_result_s:
    lookup_result_vector(0 to port_count_c-1);
  signal learn_learn_s, evict_learn_s, age_learn_s, static_learn_s:
    learn_vector(0 to port_count_c-1);

  constant idle_query_c: lookup_query_t := (
    valid => '0',
    mac => (others => x"00")
    );
  constant idle_learn_c: learn_t := (
    valid => '0',
    mac => (others => x"00")
    );

  function one_hot(index: natural) return port_mask_t
  is
    variable ret: port_mask_t := (others => '0');
  begin
    ret(index) := '1';
    return ret;
  end function;

  -- Drives one query port and returns the answer. Valid is asserted
  -- until the result pulse has been sampled, as the ingress does.
  procedure query_one(signal clock: in std_ulogic;
                      signal query: out lookup_query_vector;
                      signal result: in lookup_result_vector;
                      port_index: in natural;
                      mac: in mac48_t;
                      hit_o: out boolean;
                      mask_o: out port_mask_t)
  is
    variable timeout_v: natural := 0;
  begin
    wait until falling_edge(clock);
    query(port_index).valid <= '1';
    query(port_index).mac <= mac;

    loop
      wait until rising_edge(clock);
      exit when result(port_index).valid = '1';
      timeout_v := timeout_v + 1;
      assert timeout_v < 1000
        report "MAC table lookup never answered"
        severity failure;
    end loop;

    hit_o := result(port_index).hit = '1';
    mask_o := result(port_index).mask;

    wait until falling_edge(clock);
    query(port_index).valid <= '0';
  end procedure;

  -- Asserts a query on every port at once and collects the answers as
  -- they come.
  procedure query_all(signal clock: in std_ulogic;
                      signal query: out lookup_query_vector;
                      signal result: in lookup_result_vector;
                      macs: in mac48_vector;
                      hit_o: out bool_vector;
                      mask_o: out mask_vector)
  is
    variable seen_v: bool_vector(0 to macs'length-1) := (others => false);
    variable pending_v: natural := macs'length;
    variable timeout_v: natural := 0;
  begin
    wait until falling_edge(clock);
    for p in 0 to macs'length-1
    loop
      query(p).valid <= '1';
      query(p).mac <= macs(macs'low + p);
    end loop;

    while pending_v /= 0
    loop
      wait until rising_edge(clock);

      for p in 0 to macs'length-1
      loop
        if result(p).valid = '1' and not seen_v(p) then
          seen_v(p) := true;
          hit_o(p) := result(p).hit = '1';
          mask_o(p) := result(p).mask;
          pending_v := pending_v - 1;
        end if;
      end loop;

      wait until falling_edge(clock);

      for p in 0 to macs'length-1
      loop
        if seen_v(p) then
          query(p).valid <= '0';
        end if;
      end loop;

      timeout_v := timeout_v + 1;
      assert timeout_v < 1000
        report "MAC table lookup never answered"
        severity failure;
    end loop;
  end procedure;

  procedure learn_one(signal clock: in std_ulogic;
                      signal learn: out learn_vector;
                      port_index: in natural;
                      mac: in mac48_t)
  is
  begin
    wait until falling_edge(clock);
    learn(port_index).valid <= '1';
    learn(port_index).mac <= mac;
    wait until falling_edge(clock);
    learn(port_index).valid <= '0';
    -- Let the learn walk the pipeline, arbitration and write-back
    -- included, before the next stimulus.
    for i in 1 to 24
    loop
      wait until falling_edge(clock);
    end loop;
  end procedure;

  -- Pulses a learn strobe and starts a query for the same address on
  -- the same cycle, so that both travel the lookup pipeline together.
  -- The learn outranks the query in arbitration and the write-back
  -- hazard bubble holds the query back until the entry has reached the
  -- table, so the racing query must already see it: a bubble too short
  -- to cover the whole write-back would answer from pre-write bucket
  -- contents and fail the caller's check.
  procedure learn_racing_query(signal clock: in std_ulogic;
                               signal learn: out learn_vector;
                               signal query: out lookup_query_vector;
                               signal result: in lookup_result_vector;
                               learn_port: in natural;
                               query_port: in natural;
                               mac: in mac48_t;
                               hit_o: out boolean;
                               mask_o: out port_mask_t)
  is
    variable timeout_v: natural := 0;
  begin
    wait until falling_edge(clock);
    learn(learn_port).valid <= '1';
    learn(learn_port).mac <= mac;
    query(query_port).valid <= '1';
    query(query_port).mac <= mac;

    wait until falling_edge(clock);
    learn(learn_port).valid <= '0';

    loop
      wait until rising_edge(clock);
      exit when result(query_port).valid = '1';
      timeout_v := timeout_v + 1;
      assert timeout_v < 1000
        report "MAC table lookup never answered"
        severity failure;
    end loop;

    hit_o := result(query_port).hit = '1';
    mask_o := result(query_port).mask;

    wait until falling_edge(clock);
    query(query_port).valid <= '0';
  end procedure;

  procedure check_hit(name: in string;
                      what: in string;
                      hit: in boolean;
                      mask: in port_mask_t;
                      expected_port: in natural)
  is
  begin
    assert_equal(name, what&" hit", hit, true, FAILURE);
    assert_equal(name, what&" mask", mask, one_hot(expected_port), FAILURE);
  end procedure;

begin

  learning: process is
    constant name_c: string := "learning";
    variable hit_v: boolean;
    variable mask_v: port_mask_t;
    variable hits_v: bool_vector(0 to port_count_c-1);
    variable masks_v: mask_vector(0 to port_count_c-1);
    variable macs_v: mac48_vector(0 to port_count_c-1);
  begin
    done_s(0) <= '0';
    learn_query_s <= (others => idle_query_c);
    learn_learn_s <= (others => idle_learn_c);

    wait for 40 ns;

    -- An empty table misses.
    query_one(clock_s, learn_query_s, learn_result_s, 0, mac_a_c, hit_v, mask_v);
    assert_equal(name_c, "cold lookup hit", hit_v, false, FAILURE);

    -- Learn on port 2, every other port sees it there.
    learn_one(clock_s, learn_learn_s, 2, mac_a_c);
    for p in 0 to port_count_c-1
    loop
      query_one(clock_s, learn_query_s, learn_result_s, p, mac_a_c, hit_v, mask_v);
      check_hit(name_c, "lookup from port "&to_string(p), hit_v, mask_v, 2);
    end loop;

    -- Station move to port 3.
    learn_one(clock_s, learn_learn_s, 3, mac_a_c);
    query_one(clock_s, learn_query_s, learn_result_s, 0, mac_a_c, hit_v, mask_v);
    check_hit(name_c, "lookup after station move", hit_v, mask_v, 3);

    -- A group address is never learned, whatever the port claims.
    learn_one(clock_s, learn_learn_s, 1, mac_group_c);
    learn_one(clock_s, learn_learn_s, 1, ethernet_broadcast_addr_c);
    query_one(clock_s, learn_query_s, learn_result_s, 0, mac_group_c, hit_v, mask_v);
    assert_equal(name_c, "group address lookup hit", hit_v, false, FAILURE);
    query_one(clock_s, learn_query_s, learn_result_s, 0,
              ethernet_broadcast_addr_c, hit_v, mask_v);
    assert_equal(name_c, "broadcast lookup hit", hit_v, false, FAILURE);

    -- Four ports querying at once get four independent answers.
    learn_one(clock_s, learn_learn_s, 1, mac_b_c);
    learn_one(clock_s, learn_learn_s, 2, mac_c_c);

    macs_v := (mac_a_c, mac_b_c, mac_unknown_c, mac_c_c);
    query_all(clock_s, learn_query_s, learn_result_s, macs_v, hits_v, masks_v);
    check_hit(name_c, "concurrent lookup 0", hits_v(0), masks_v(0), 3);
    check_hit(name_c, "concurrent lookup 1", hits_v(1), masks_v(1), 1);
    assert_equal(name_c, "concurrent lookup 2 hit", hits_v(2), false, FAILURE);
    check_hit(name_c, "concurrent lookup 3", hits_v(3), masks_v(3), 2);

    -- A learn and a lookup of the same address in the pipeline at the
    -- same time. The write-back bubble orders them, so both the racing
    -- lookup and the next one see the entry the learn left behind.
    learn_racing_query(clock_s, learn_learn_s, learn_query_s, learn_result_s,
                       0, 1, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "racing lookup", hit_v, mask_v, 0);
    query_one(clock_s, learn_query_s, learn_result_s, 1, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "lookup after racing learn", hit_v, mask_v, 0);

    -- Same race on an address already in the table, so the write-back
    -- refreshes a way instead of taking a free one.
    learn_racing_query(clock_s, learn_learn_s, learn_query_s, learn_result_s,
                       2, 3, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "racing station move lookup", hit_v, mask_v, 2);
    query_one(clock_s, learn_query_s, learn_result_s, 3, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "lookup after racing station move", hit_v, mask_v, 2);

    log_info(name_c, "done");
    done_s(0) <= '1';

    wait;
  end process;

  eviction: process is
    constant name_c: string := "eviction";
    variable hit_v: boolean;
    variable mask_v: port_mask_t;
  begin
    done_s(1) <= '0';
    evict_query_s <= (others => idle_query_c);
    evict_learn_s <= (others => idle_learn_c);

    wait for 40 ns;

    learn_one(clock_s, evict_learn_s, 0, mac_a_c);
    learn_one(clock_s, evict_learn_s, 1, mac_b_c);

    query_one(clock_s, evict_query_s, evict_result_s, 0, mac_a_c, hit_v, mask_v);
    check_hit(name_c, "first way", hit_v, mask_v, 0);
    query_one(clock_s, evict_query_s, evict_result_s, 0, mac_b_c, hit_v, mask_v);
    check_hit(name_c, "second way", hit_v, mask_v, 1);

    -- The bucket is full of fresh entries, so the round-robin victim
    -- pointer decides, and it points at the way holding mac_a_c.
    learn_one(clock_s, evict_learn_s, 2, mac_c_c);

    query_one(clock_s, evict_query_s, evict_result_s, 0, mac_c_c, hit_v, mask_v);
    check_hit(name_c, "third address", hit_v, mask_v, 2);
    query_one(clock_s, evict_query_s, evict_result_s, 0, mac_b_c, hit_v, mask_v);
    check_hit(name_c, "surviving address", hit_v, mask_v, 1);
    query_one(clock_s, evict_query_s, evict_result_s, 0, mac_a_c, hit_v, mask_v);
    assert_equal(name_c, "evicted address hit", hit_v, false, FAILURE);

    log_info(name_c, "done");
    done_s(1) <= '1';

    wait;
  end process;

  aging: process is
    constant name_c: string := "aging";
    variable hit_v: boolean;
    variable mask_v: port_mask_t;
  begin
    done_s(2) <= '0';
    age_query_s <= (others => idle_query_c);
    age_learn_s <= (others => idle_learn_c);

    wait for 40 ns;

    learn_one(clock_s, age_learn_s, 1, mac_d_c);
    query_one(clock_s, age_query_s, age_result_s, 0, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "fresh entry", hit_v, mask_v, 1);

    -- An entry cannot die before the sweep has gone around the whole
    -- table once.
    for i in 1 to (3 * age_nominal_c) / 4
    loop
      wait until falling_edge(clock_s);
    end loop;

    query_one(clock_s, age_query_s, age_result_s, 0, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "entry below nominal age", hit_v, mask_v, 1);

    -- Lookups do not refresh, only learning does, so past two sweeps
    -- the entry is gone for sure.
    for i in 1 to 3 * age_nominal_c
    loop
      wait until falling_edge(clock_s);
    end loop;

    query_one(clock_s, age_query_s, age_result_s, 0, mac_d_c, hit_v, mask_v);
    assert_equal(name_c, "expired entry hit", hit_v, false, FAILURE);

    -- Relearning after expiry works.
    learn_one(clock_s, age_learn_s, 3, mac_d_c);
    query_one(clock_s, age_query_s, age_result_s, 2, mac_d_c, hit_v, mask_v);
    check_hit(name_c, "relearned entry", hit_v, mask_v, 3);

    log_info(name_c, "done");
    done_s(2) <= '1';

    wait;
  end process;

  static: process is
    constant name_c: string := "static";
    variable hit_v: boolean;
    variable mask_v: port_mask_t;
  begin
    done_s(3) <= '0';
    static_query_s <= (others => idle_query_c);
    static_learn_s <= (others => idle_learn_c);

    wait for 40 ns;

    for i in 0 to static_macs_c'length-1
    loop
      query_one(clock_s, static_query_s, static_result_s, i mod port_count_c,
                static_macs_c(i), hit_v, mask_v);
      check_hit(name_c, "static entry "&to_string(i), hit_v, mask_v, static_ports_c(i));
    end loop;

    query_one(clock_s, static_query_s, static_result_s, 0,
              mac_unknown_c, hit_v, mask_v);
    assert_equal(name_c, "unlisted address hit", hit_v, false, FAILURE);

    -- Learning is disabled, the strobe changes nothing.
    learn_one(clock_s, static_learn_s, 2, mac_unknown_c);
    query_one(clock_s, static_query_s, static_result_s, 0,
              mac_unknown_c, hit_v, mask_v);
    assert_equal(name_c, "address learned in static mode", hit_v, false, FAILURE);

    learn_one(clock_s, static_learn_s, 2, mac_a_c);
    query_one(clock_s, static_query_s, static_result_s, 1, mac_a_c, hit_v, mask_v);
    check_hit(name_c, "static entry after learn strobe", hit_v, mask_v, static_ports_c(0));

    log_info(name_c, "done");
    done_s(3) <= '1';

    wait;
  end process;

  learn_dut: nsl_inet.switching.switching_mac_table
    generic map(
      config_c => learn_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      query_i => learn_query_s,
      result_o => learn_result_s,
      learn_i => learn_learn_s
      );

  evict_dut: nsl_inet.switching.switching_mac_table
    generic map(
      config_c => evict_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      query_i => evict_query_s,
      result_o => evict_result_s,
      learn_i => evict_learn_s
      );

  age_dut: nsl_inet.switching.switching_mac_table
    generic map(
      config_c => age_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      query_i => age_query_s,
      result_o => age_result_s,
      learn_i => age_learn_s
      );

  static_dut: nsl_inet.switching.switching_mac_table
    generic map(
      config_c => static_config_c,
      static_macs_c => static_macs_c,
      static_ports_c => static_ports_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      query_i => static_query_s,
      result_o => static_result_s,
      learn_i => static_learn_s
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
