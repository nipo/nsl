library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_math, nsl_mii, nsl_time, nsl_ptp, nsl_simulation, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;
use nsl_ptp.ptp.all;

entity tb is
end tb;

-- The master alone, its transmit strobe answered at once and one
-- Delay_Req fed in: every kind of message it emits is parsed for the
-- header fields a slave reads, the time property flags, the log
-- intervals and the UTC offset.
architecture arch of tb is

  constant clock_period_c : time := 10 ns;
  -- A second of master time in this many cycles.
  constant tick_hz_c : natural := 1000;
  constant cfg_c : config_t := stream_config(1);
  constant blocks_c : integer_vector(0 to 1)
    := (tag_length_c, l2_context_length_c);
  constant hdr_c : natural := tag_length_c + l2_context_length_c;
  constant identity_c : byte_string(0 to 7) := from_hex("0221cafeff6d0000");
  constant utc_offset_c : integer := 37;
  constant delay_req_log_c : integer := -2;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal rx_s, tx_s : bus_t;
  signal time_s : timestamp_t;
  signal utc_s : signed(15 downto 0);

  signal seen_sync_s, seen_follow_up_s, seen_announce_s, seen_delay_resp_s
    : boolean := false;

begin

  time_s.second <= to_unsigned(5, time_s.second'length);
  time_s.nanosecond <= (others => '0');
  time_s.abs_change <= '0';
  utc_s <= to_signed(utc_offset_c, 16);

  dut: nsl_ptp.stream_l2.ptp_l2_master
    generic map(
      config_c => cfg_c,
      header_length_c => blocks_c,
      clock_i_hz_c => tick_hz_c,
      sync_period_c => 1,
      announce_c => true,
      announce_period_c => 2,
      delay_req_log_interval_c => delay_req_log_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      clock_identity_i => identity_c,
      clock_class_i => to_unsigned(ptp_clock_class_locked_c, 8),
      time_source_i => ptp_time_source_gps_c,
      utc_offset_i => utc_s,
      utc_offset_valid_i => '1',
      traceable_i => '1',

      capture_id_o => open,
      capture_time_i => time_s,

      tx_strobe_i => '1',
      tx_capture_time_i => time_s,

      rx_i => rx_s.m,
      rx_o => rx_s.s,
      tx_o => tx_s.m,
      tx_i => tx_s.s
      );

  tx_s.s <= accept(cfg_c, true);

  -- One Delay_Req, after the first Sync went out.
  feed: process
    constant req_c : byte_string(0 to hdr_c + ptp_delay_req_length_c - 1)
      := (others => x"00");
    variable frame : byte_string(req_c'range) := req_c;
  begin
    rx_s.m <= transfer(cfg_c, bytes => (0 => x"00"), user => "0", valid => false);
    frame(hdr_c + ptp_off_type_c) := to_byte(ptp_msg_delay_req_c);
    frame(hdr_c + ptp_off_version_c) := x"02";
    frame(hdr_c + ptp_off_length_c + 1) := to_byte(ptp_delay_req_length_c);
    frame(hdr_c + ptp_off_source_port_identity_c) := x"11";
    frame(hdr_c + ptp_off_sequence_id_c + 1) := x"07";
    frame(hdr_c + ptp_off_control_c) := x"01";
    wait until reset_n_s = '1';
    for i in 1 to 1500 loop
      wait until rising_edge(clock_s);
    end loop;
    for i in frame'range loop
      rx_s.m <= transfer(cfg_c, bytes => (0 => frame(i)), user => "0",
                         valid => true, last => i = frame'right);
      wait until rising_edge(clock_s) and is_ready(cfg_c, rx_s.s);
    end loop;
    rx_s.m <= transfer(cfg_c, bytes => (0 => x"00"), user => "0", valid => false);
    wait;
  end process;

  -- Every transmitted frame, checked by kind.
  check: process
    variable frame : byte_string(0 to 127);
    variable n : natural := 0;
    variable m : natural;
    variable kind : natural;
    variable utc : byte_string(0 to 1);
  begin
    done_s(0) <= '0';
    wait until reset_n_s = '1';
    for cycle in 1 to 5500 loop
      wait until rising_edge(clock_s);
      if is_valid(cfg_c, tx_s.m) and is_ready(cfg_c, tx_s.s) then
        frame(n) := bytes(cfg_c, tx_s.m)(0);
        n := n + 1;
        if is_last(cfg_c, tx_s.m) then
          m := hdr_c;
          kind := to_integer(unsigned(frame(m + ptp_off_type_c)(3 downto 0)));
          utc := to_be(to_unsigned(utc_offset_c, 16));
          assert frame(m + ptp_off_version_c) = x"02"
            report "version byte" severity failure;
          if kind = ptp_msg_sync_c then
            seen_sync_s <= true;
            assert frame(m + ptp_off_flags_c) = to_byte(2 ** ptp_flag0_two_step_c)
              report "Sync: two-step flag" severity failure;
            assert frame(m + ptp_off_flags_c + 1) = x"00"
              report "Sync: time property flags set" severity failure;
            assert frame(m + ptp_off_log_interval_c) = x"00"
              report "Sync: log interval" severity failure;
          elsif kind = ptp_msg_follow_up_c then
            seen_follow_up_s <= true;
            assert frame(m + ptp_off_log_interval_c) = x"00"
              report "Follow_Up: log interval" severity failure;
          elsif kind = ptp_msg_announce_c then
            seen_announce_s <= true;
            assert frame(m + ptp_off_flags_c + 1)
              = to_byte(2 ** ptp_flag1_utc_offset_valid_c
                        + 2 ** ptp_flag1_ptp_timescale_c
                        + 2 ** ptp_flag1_time_traceable_c
                        + 2 ** ptp_flag1_frequency_traceable_c)
              report "Announce: time property flags "
              & integer'image(to_integer(unsigned(frame(m + ptp_off_flags_c + 1))))
              severity failure;
            assert frame(m + ptp_off_log_interval_c) = x"01"
              report "Announce: log interval for a 2 s period" severity failure;
            assert frame(m + ptp_off_utc_offset_c to m + ptp_off_utc_offset_c + 1) = utc
              report "Announce: currentUtcOffset" severity failure;
            assert frame(m + ptp_off_gm_quality_c) = to_byte(ptp_clock_class_locked_c)
              report "Announce: clock class" severity failure;
            assert n = hdr_c + ptp_announce_length_c
              report "Announce: length " & integer'image(n) severity failure;
          elsif kind = ptp_msg_delay_resp_c then
            seen_delay_resp_s <= true;
            assert frame(m + ptp_off_log_interval_c)
              = std_ulogic_vector(to_signed(delay_req_log_c, 8))
              report "Delay_Resp: log min delay req interval" severity failure;
            assert frame(m + ptp_off_requesting_port_identity_c) = x"11"
              report "Delay_Resp: requesting port identity" severity failure;
          else
            assert false report "unexpected message kind " & integer'image(kind)
              severity failure;
          end if;
          n := 0;
        end if;
      end if;
    end loop;
    assert seen_sync_s report "no Sync seen" severity failure;
    assert seen_follow_up_s report "no Follow_Up seen" severity failure;
    assert seen_announce_s report "no Announce seen" severity failure;
    assert seen_delay_resp_s report "no Delay_Resp seen" severity failure;
    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 5,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
