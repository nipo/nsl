library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;

entity tb is
end tb;

architecture arch of tb is

  constant axi_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32,
                               id_width => 4, max_length => 16, size => true,
                               burst => true, cache => true, lock => true,
                               qos => true, region => true);
  constant apb_c : nsl_amba.apb.config_t
    := nsl_amba.apb.config(address_width => 32, data_bus_width => 32);
  constant depth_l2_c : natural := 4;
  constant depth_c : natural := 2 ** depth_l2_c;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal timestamp_s : unsigned(31 downto 0) := x"12345600";

  signal axi_s : nsl_amba.axi4_mm.bus_t;
  signal apb_s : nsl_amba.apb.bus_t;

  subtype word_t is unsigned(31 downto 0);
  type word_vector is array (natural range <>) of word_t;
  subtype entry_t is word_vector(0 to 3);
  type entry_vector is array (natural range <>) of entry_t;
  type channel_log_t is array (0 to 4) of entry_vector(0 to 31);
  type count_vector is array (0 to 4) of natural;

  constant AW : natural := 0;
  constant W : natural := 1;
  constant B : natural := 2;
  constant AR : natural := 3;
  constant R : natural := 4;

begin

  timestamp: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      timestamp_s <= timestamp_s + 1;
    end if;
  end process;

  watchdog: process is
  begin
    wait for 500 us;
    assert done_s = "1"
      report "Timeout"
      severity failure;
    wait;
  end process;

  stimulus: process is
    variable expected: channel_log_t;
    variable count: count_vector;
    variable recording: boolean;
    variable rdata: word_vector(0 to 15);

    procedure record_entry(c: natural; w0, w1, w2, w3: word_t) is
    begin
      if recording then
        if count(c) < 32 then
          expected(c)(count(c)) := (w0, w1, w2, w3);
        end if;
        count(c) := count(c) + 1;
      end if;
    end procedure;

    procedure reg_check(what: string; offset: natural; val: word_t) is
      variable v: unsigned(31 downto 0);
      variable err: boolean;
    begin
      nsl_amba.apb.apb_read(apb_c, clock_s, apb_s.s, apb_s.m,
                            addr => to_unsigned(offset, 32),
                            val => v, err => err);
      assert_equal(what & " @" & to_string(to_unsigned(offset, 16)),
                   std_ulogic_vector(v), std_ulogic_vector(val), failure);
    end procedure;

    procedure reg_write(offset: natural; val: word_t) is
      variable err: boolean;
    begin
      nsl_amba.apb.apb_write(apb_c, clock_s, apb_s.s, apb_s.m,
                             addr => to_unsigned(offset, 32),
                             val => val, err => err);
    end procedure;

    procedure axi_write(addr: natural; txn_id: natural; data: word_vector;
                        strb: std_ulogic_vector(3 downto 0) := "1111";
                        cache, prot, qos, region: natural := 0;
                        w_gap: natural := 0;
                        b_delay: natural := 0) is
      alias xdata: word_vector(0 to data'length-1) is data;
      variable stall: natural;
      variable last: natural;
    begin
      axi_s.m.aw <= address(axi_c,
                            id => std_ulogic_vector(to_unsigned(txn_id, 4)),
                            addr => to_unsigned(addr, 32),
                            len_m1 => to_unsigned(xdata'length-1, 4),
                            size_l2 => "010",
                            burst => BURST_INCR,
                            cache => std_ulogic_vector(to_unsigned(cache, 4)),
                            prot => std_ulogic_vector(to_unsigned(prot, 3)),
                            qos => std_ulogic_vector(to_unsigned(qos, 4)),
                            region => std_ulogic_vector(to_unsigned(region, 4)));
      stall := 0;
      loop
        wait until rising_edge(clock_s);
        exit when is_ready(axi_c, axi_s.s.aw);
        stall := stall + 1;
      end loop;
      record_entry(AW, timestamp_s, to_unsigned(addr, 32),
                   to_unsigned(txn_id + (xdata'length-1) * 2**16 + 2 * 2**24 + 1 * 2**27, 32),
                   to_unsigned(cache + prot * 2**4 + qos * 2**8 + region * 2**12 + stall * 2**24, 32));
      wait until falling_edge(clock_s);
      axi_s.m.aw <= address_defaults(axi_c);

      for i in xdata'range
      loop
        for g in 1 to w_gap
        loop
          wait until falling_edge(clock_s);
        end loop;

        axi_s.m.w <= write_data(axi_c, value => xdata(i), strb => strb,
                                endian => ENDIAN_LITTLE,
                                last => i = xdata'right);
        stall := 0;
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(axi_c, axi_s.s.w);
          stall := stall + 1;
        end loop;
        last := 0;
        if i = xdata'right then
          last := 1;
        end if;
        record_entry(W, timestamp_s, xdata(i), x"00000000",
                     to_unsigned(to_integer(unsigned(strb)) + last * 2**8 + stall * 2**24, 32));
        wait until falling_edge(clock_s);
        axi_s.m.w <= write_data_defaults(axi_c);
      end loop;

      axi_s.m.b <= accept(axi_c, b_delay = 0);
      loop
        wait until rising_edge(clock_s);
        exit when is_valid(axi_c, axi_s.s.b);
      end loop;
      stall := 0;
      if b_delay /= 0 then
        stall := 1;
        for d in 2 to b_delay
        loop
          wait until falling_edge(clock_s);
          wait until rising_edge(clock_s);
          assert is_valid(axi_c, axi_s.s.b) report "B valid dropped" severity failure;
          stall := stall + 1;
        end loop;
        wait until falling_edge(clock_s);
        axi_s.m.b <= accept(axi_c, true);
        wait until rising_edge(clock_s);
        assert is_valid(axi_c, axi_s.s.b) report "B valid dropped" severity failure;
      end if;
      assert_equal("B ID", id(axi_c, axi_s.s.b), std_ulogic_vector(to_unsigned(txn_id, 4)), failure);
      record_entry(B, timestamp_s,
                   to_unsigned(txn_id + to_integer(unsigned(axi_s.s.b.resp)) * 2**16, 32),
                   x"00000000",
                   to_unsigned(stall * 2**24, 32));
      wait until falling_edge(clock_s);
      axi_s.m.b <= accept(axi_c, false);
    end procedure;

    procedure axi_read(addr: natural; txn_id: natural; beats: natural;
                       lock: boolean := false;
                       r_delay: natural := 0) is
      variable stall: natural;
      variable lock_v: natural;
      variable last: natural;
      variable lock_e: lock_enum_t;
    begin
      lock_v := 0;
      lock_e := LOCK_NORMAL;
      if lock then
        lock_v := 1;
        lock_e := LOCK_EXCLUSIVE;
      end if;
      axi_s.m.ar <= address(axi_c,
                            id => std_ulogic_vector(to_unsigned(txn_id, 4)),
                            addr => to_unsigned(addr, 32),
                            len_m1 => to_unsigned(beats-1, 4),
                            size_l2 => "010",
                            burst => BURST_INCR,
                            lock => lock_e);
      stall := 0;
      loop
        wait until rising_edge(clock_s);
        exit when is_ready(axi_c, axi_s.s.ar);
        stall := stall + 1;
      end loop;
      record_entry(AR, timestamp_s, to_unsigned(addr, 32),
                   to_unsigned(txn_id + (beats-1) * 2**16 + 2 * 2**24 + 1 * 2**27 + lock_v * 2**29, 32),
                   to_unsigned(stall * 2**24, 32));
      wait until falling_edge(clock_s);
      axi_s.m.ar <= address_defaults(axi_c);

      for i in 0 to beats-1
      loop
        axi_s.m.r <= accept(axi_c, r_delay = 0);
        loop
          wait until rising_edge(clock_s);
          exit when is_valid(axi_c, axi_s.s.r);
        end loop;
        stall := 0;
        if r_delay /= 0 then
          stall := 1;
          for d in 2 to r_delay
          loop
            wait until falling_edge(clock_s);
            wait until rising_edge(clock_s);
            assert is_valid(axi_c, axi_s.s.r) report "R valid dropped" severity failure;
            stall := stall + 1;
          end loop;
          wait until falling_edge(clock_s);
          axi_s.m.r <= accept(axi_c, true);
          wait until rising_edge(clock_s);
          assert is_valid(axi_c, axi_s.s.r) report "R valid dropped" severity failure;
        end if;

        assert_equal("R ID", id(axi_c, axi_s.s.r), std_ulogic_vector(to_unsigned(txn_id, 4)), failure);
        assert is_last(axi_c, axi_s.s.r) = (i = beats-1)
          report "Bad R last" severity failure;
        rdata(i) := value(axi_c, axi_s.s.r, ENDIAN_LITTLE);
        last := 0;
        if i = beats-1 then
          last := 1;
        end if;
        record_entry(R, timestamp_s, rdata(i), x"00000000",
                     to_unsigned(txn_id + to_integer(unsigned(axi_s.s.r.resp)) * 2**16
                                 + last * 2**18 + stall * 2**24, 32));
        wait until falling_edge(clock_s);
        axi_s.m.r <= accept(axi_c, false);
      end loop;
    end procedure;

    procedure log_check is
      variable n: natural;
      variable overflow: natural;
    begin
      overflow := 0;
      for c in 0 to 4
      loop
        n := count(c);
        if n > depth_c then
          n := depth_c;
          overflow := overflow + 2**c;
        end if;
        reg_check("COUNT(" & to_string(c) & ")", 16#10# + 4 * c, to_unsigned(n, 32));
        for i in 0 to n-1
        loop
          for wi in 0 to 3
          loop
            reg_check("Channel " & to_string(c) & " entry " & to_string(i) & " word " & to_string(wi),
                      (c + 1) * 2**(depth_l2_c + 4) + 16 * i + 4 * wi,
                      expected(c)(i)(wi));
          end loop;
        end loop;
      end loop;
      reg_check("STATUS", 16#004#, to_unsigned(overflow, 32));
    end procedure;

    procedure log_reset is
    begin
      count := (others => 0);
    end procedure;

    variable ts: unsigned(31 downto 0);
    variable err: boolean;
    variable ts_before: unsigned(31 downto 0);
  begin
    done_s <= "0";
    axi_s.m <= (aw => address_defaults(axi_c),
                w => write_data_defaults(axi_c),
                b => accept(axi_c, false),
                ar => address_defaults(axi_c),
                r => accept(axi_c, false));
    apb_s.m <= nsl_amba.apb.transfer_idle(apb_c);
    recording := false;
    log_reset;

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    log_info("Idle state");
    reg_check("CTRL", 16#000#, x"00000000");
    reg_check("CONFIG", 16#00c#, to_unsigned(depth_l2_c + 2 * 2**8 + 4 * 2**16, 32));
    log_check;
    ts_before := timestamp_s;
    nsl_amba.apb.apb_read(apb_c, clock_s, apb_s.s, apb_s.m,
                          addr => to_unsigned(16#008#, 32), val => ts, err => err);
    assert ts >= ts_before and ts < timestamp_s
      report "TIMESTAMP out of range: " & to_string(ts) & " not in "
      & to_string(ts_before) & " .. " & to_string(timestamp_s)
      severity failure;
    reg_check("Unmapped", 16#080#, x"00000000");
    reg_check("Unmapped", 6 * 2**(depth_l2_c + 4), x"00000000");

    log_info("Traffic while disabled");
    axi_write(16#100#, 1, word_vector'(0 => x"deadbeef"));
    axi_read(16#100#, 1, 1);
    log_check;

    log_info("Traffic while enabled");
    reg_write(16#000#, x"00000001");
    reg_check("CTRL", 16#000#, x"00000001");
    recording := true;
    axi_write(16#100#, 3, word_vector'(0 => x"11223344"),
              cache => 3, prot => 2, qos => 5, region => 9, b_delay => 3);
    axi_write(16#200#, 5, word_vector'(x"00010203", x"04050607", x"08090a0b", x"0c0d0e0f"),
              w_gap => 1);
    axi_write(16#300#, 1, word_vector'(0 => x"a5a5a5a5"), strb => "0110", b_delay => 1);
    axi_read(16#100#, 2, 1, lock => true, r_delay => 2);
    assert rdata(0) = x"11223344" report "Bad readback" severity failure;
    axi_read(16#200#, 7, 4, r_delay => 1);
    assert rdata(0 to 3) = word_vector'(x"00010203", x"04050607", x"08090a0b", x"0c0d0e0f")
      report "Bad readback" severity failure;
    axi_read(16#200#, 6, 4);
    reg_write(16#000#, x"00000000");
    recording := false;
    reg_check("CTRL", 16#000#, x"00000000");

    assert expected(B)(0)(3) = to_unsigned(3 * 2**24, 32)
      report "B backpressure did not happen" severity failure;
    assert expected(R)(0)(3)(31 downto 24) = to_unsigned(2, 8)
      report "R backpressure did not happen" severity failure;
    log_check;

    log_info("Overflow");
    reg_write(16#000#, x"00000002");
    log_reset;
    log_check;
    reg_write(16#000#, x"00000001");
    recording := true;
    for i in 0 to depth_c + 1
    loop
      axi_write(16#400# + 4 * i, i mod 16, word_vector'(0 => to_unsigned(i, 32)));
    end loop;
    axi_read(16#400#, 0, 1);
    reg_write(16#000#, x"00000000");
    recording := false;
    log_check;

    log_info("Clear");
    reg_write(16#000#, x"00000003");
    log_reset;
    reg_check("CTRL", 16#000#, x"00000001");
    reg_write(16#000#, x"00000000");
    log_check;

    done_s <= "1";
    wait;
  end process;

  ram: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => axi_c,
      byte_size_l2_c => 12
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s
      );

  dut: nsl_amba.mm_logger.axi4_mm_logger
    generic map(
      axi_config_c => axi_c,
      apb_config_c => apb_c,
      depth_l2_c => depth_l2_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      timestamp_i => timestamp_s,
      master_i => axi_s.m,
      slave_i => axi_s.s,
      apb_i => apb_s.m,
      apb_o => apb_s.s
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
