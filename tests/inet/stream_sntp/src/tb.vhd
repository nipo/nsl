library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.ipv4.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ipv4.all;
use nsl_inet.stream_udp.all;
use nsl_inet.stream_sntp.all;

-- An SNTP client against a bench server.  The server checks the poll
-- layout, refuses the client the replies it must not take, then walks
-- it through two synchronizations, checking the running clock in
-- between and the shutdown at the end.
entity tb is
end tb;

architecture arch of tb is

  constant cfg_c : config_t := stream_config(1);
  constant hdr_c : integer_vector(0 to 3) := (5, 7, 7, 2);
  constant pre_size_c : natural := context_byte_count(cfg_c, hdr_c);
  constant prefix_c : byte_string(0 to pre_size_c-1) := (others => x"5a");

  constant ctx_size_c : natural
    := ip_context_length_c + udp_context_length_c;
  constant tx_length_c : natural := ctx_size_c + sntp_message_length_c;

  -- Protocol second, as the ticker divider and as bench time
  constant client_hz_c : natural := 100;
  constant tick_c : time := 1 us;
  constant poll_period_c : natural := 6;

  constant server_ip_c : ipv4_t := to_ipv4(192, 168, 1, 1);

  constant client_flags_c : byte := x"23";
  constant server_flags_c : byte := x"24";

  constant zero8_c : byte_string(0 to 7) := (others => x"00");
  constant zero39_c : byte_string(0 to 38) := (others => x"00");

  constant t3_c : unsigned(63 downto 0) := x"e7a1b2c311223344";
  constant t3b_c : unsigned(63 downto 0) := x"e8000001aabbccdd";
  constant t3c_c : unsigned(63 downto 0) := x"f000000055667788";

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal rx_s, tx_s : bus_t;
  signal enable_s, server_valid_s : std_ulogic;
  signal time_s : unsigned(63 downto 0);
  signal tick_s, valid_s : std_ulogic;

  -- SNTP reply message, the timestamps the server owns filled with
  -- the transmit one.
  function reply(flags: byte;
                 stratum: byte;
                 originate: byte_string;
                 transmit: unsigned) return byte_string
  is
    variable msg_v: byte_string(0 to sntp_message_length_c-1)
      := (others => x"00");
  begin
    msg_v(sntp_flags_offset_c) := flags;
    msg_v(sntp_stratum_offset_c) := stratum;
    msg_v(sntp_reference_ts_offset_c to sntp_reference_ts_offset_c+7)
      := to_be(transmit);
    msg_v(sntp_originate_ts_offset_c to sntp_originate_ts_offset_c+7)
      := originate;
    msg_v(sntp_receive_ts_offset_c to sntp_receive_ts_offset_c+7)
      := to_be(transmit);
    msg_v(sntp_transmit_ts_offset_c to sntp_transmit_ts_offset_c+7)
      := to_be(transmit);

    return msg_v;
  end function;

begin

  server: process is
    variable beat_v: master_t;
    variable rx_v: byte_stream;
    variable nonce_v, nonce2_v: byte_string(0 to 7);
    variable base_v: unsigned(63 downto 0);
    variable poll_time_v: time;

    procedure tx_get is
    begin
      clear(rx_v);
      loop
        receive(cfg_c, clock_s, tx_s.m, tx_s.s, beat_v);
        for k in 0 to byte_count(cfg_c, beat_v)-1
        loop
          write(rx_v, beat_v.data(k));
        end loop;
        if is_last(cfg_c, beat_v) then
          exit;
        end if;
      end loop;

      assert not is_rejected(cfg_c, beat_v)
        report "Client must not emit rejected packets"
        severity failure;
      assert_equal("tx length", rx_v.all'length, tx_length_c, failure);
    end procedure;

    procedure expect_idle(constant cycles: natural;
                          constant what: string) is
    begin
      for i in 1 to cycles
      loop
        wait until rising_edge(clock_s);
        assert not is_valid(cfg_c, tx_s.m)
          report what
          severity failure;
      end loop;
    end procedure;

    -- Byte of the context block prefix.
    impure function cb(k: integer) return byte is
    begin
      return rx_v.all(k);
    end function;

    impure function cs(f, l: integer) return byte_string is
    begin
      return rx_v.all(f to l);
    end function;

    -- Byte of the SNTP message.
    impure function ps(f, l: integer) return byte_string is
    begin
      return rx_v.all(ctx_size_c + f to ctx_size_c + l);
    end function;

    impure function pb(k: integer) return byte is
    begin
      return rx_v.all(ctx_size_c + k);
    end function;

    -- Checks the whole layout of a poll and returns its nonce.
    impure function check_poll(constant what: string) return byte_string is
    begin
      assert_equal(what & " ip peer", cs(0, 3), server_ip_c, failure);
      assert_equal(what & " ip casting", cb(4), to_byte(0), failure);
      assert_equal(what & " ip length", to_integer(from_be(cs(5, 6))),
                   udp_header_length_c + sntp_message_length_c, failure);
      assert_equal(what & " udp peer port",
                   to_integer(from_be(cs(ip_context_length_c,
                                         ip_context_length_c+1))),
                   sntp_port_c, failure);
      assert_equal(what & " flags", pb(sntp_flags_offset_c),
                   client_flags_c, failure);
      assert_equal(what & " body", ps(1, 39), zero39_c, failure);
      assert_different(what & " nonce",
                       ps(sntp_transmit_ts_offset_c,
                          sntp_transmit_ts_offset_c+7),
                       zero8_c, failure);

      return ps(sntp_transmit_ts_offset_c, sntp_transmit_ts_offset_c+7);
    end function;
  begin
    tx_s.s <= accept(cfg_c, false);
    rx_s.m <= transfer_defaults(cfg_c);
    enable_s <= '1';
    server_valid_s <= '0';
    wait for 100 ns;

    -- No server, no traffic
    expect_idle(400, "Client must not poll without a server address");
    assert_equal("idle valid", valid_s, '0', failure);

    server_valid_s <= '1';

    -- First poll
    tx_get;
    nonce_v := check_poll("poll");

    -- A reply echoing another request must not be taken
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(server_flags_c, to_byte(2),
                                           not nonce_v, t3_c),
                user => "0");
    wait for tick_c;
    assert_equal("reply with a foreign originate timestamp", valid_s, '0',
                 failure);

    -- A kiss-o'-death reply carries no time
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(server_flags_c, to_byte(0),
                                           nonce_v, t3_c),
                user => "0");
    wait for tick_c;
    assert_equal("kiss-o'-death reply", valid_s, '0', failure);

    -- Synchronization
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(server_flags_c, to_byte(2),
                                           nonce_v, t3_c),
                user => "0");

    wait until valid_s = '1' for 5 * tick_c;
    assert_equal("synchronized", valid_s, '1', failure);
    wait until rising_edge(clock_s);
    assert_equal("time at synchronization", time_s, t3_c, failure);

    -- The clock runs on the local ticker between polls
    wait until rising_edge(clock_s) and tick_s = '0' for 2 * tick_c;
    base_v := time_s;
    wait until rising_edge(clock_s) and tick_s = '1' for 3 * tick_c;
    assert_equal("tick pulse", tick_s, '1', failure);
    assert_equal("running seconds", time_s(63 downto 32),
                 base_v(63 downto 32) + 1, failure);
    assert_equal("fraction between ticks", time_s(31 downto 0),
                 base_v(31 downto 0), failure);
    poll_time_v := now;

    -- Next poll, with a nonce of its own
    tx_get;
    assert now - poll_time_v > 3 * tick_c
      and now - poll_time_v < (poll_period_c + 2) * tick_c
      report "Poll must happen one poll period after synchronization"
      severity failure;
    nonce2_v := check_poll("repoll");
    assert_different("repoll nonce", nonce2_v, nonce_v, failure);

    -- Resynchronization on a jumped server clock
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(server_flags_c, to_byte(2),
                                           nonce2_v, t3b_c),
                user => "0");

    wait until time_s(31 downto 0) = t3b_c(31 downto 0) for 5 * tick_c;
    wait until rising_edge(clock_s);
    assert_equal("time at resynchronization", time_s, t3b_c, failure);

    -- A rejected reply carries no time
    packet_send(cfg_c, clock_s, rx_s.s, rx_s.m,
                packet => prefix_c & reply(server_flags_c, to_byte(2),
                                           nonce2_v, t3c_c),
                user => "1");
    wait for tick_c;
    assert_equal("still synchronized after a rejected reply", valid_s, '1',
                 failure);
    wait until rising_edge(clock_s);
    assert_equal("fraction after a rejected reply", time_s(31 downto 0),
                 t3b_c(31 downto 0), failure);

    -- Shutdown
    enable_s <= '0';
    wait until valid_s = '0' for 5 * tick_c;
    assert_equal("time dropped", valid_s, '0', failure);
    wait until rising_edge(clock_s);
    assert_equal("time zeroed", time_s, to_unsigned(0, 64), failure);
    expect_idle(400, "Disabled client must not poll");

    log_info("SNTP client OK");
    done_s(0) <= '1';
    wait;
  end process;

  watchdog: process is
  begin
    wait for 200 us;
    assert false
      report "Simulation did not complete in time"
      severity failure;
    wait;
  end process;

  dut: nsl_inet.stream_sntp.stream_sntp_client
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => client_hz_c,
      poll_period_c => poll_period_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      enable_i => enable_s,
      server_i => server_ip_c,
      server_valid_i => server_valid_s,

      rx_i => rx_s.m,
      rx_o => rx_s.s,
      tx_o => tx_s.m,
      tx_i => tx_s.s,

      time_o => time_s,
      tick_o => tick_s,
      valid_o => valid_s
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
