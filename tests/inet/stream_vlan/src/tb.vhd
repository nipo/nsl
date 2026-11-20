library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.vlan.all;
use nsl_inet.stream_vlan.all;

-- Stream counterpart of the bnoc vlan test (tests/inet/vlan), same
-- frames and scenarios, run at every stream width:
--
-- * demux with a native VLAN: untagged, VID 100, unknown VID 300
--   (dropped), VID 200 with priority bits, native-tagged and
--   rejected untagged frames;
--
-- * mux: one frame per pipe, the native one leaving untagged;
--
-- * demux with the default native VLAN, absent from the VID list:
--   untagged frames are dropped;
--
-- * demux and mux back to back: tagged frames come back with priority
--   discarded, native-tagged ones come back untagged.
--
-- Frames take the mac side geometry: the ethernet frame block front
-- padding precedes the bnoc frame bytes.  Untagged and native-tagged
-- frames take distinct paths through the demux, so outputs merging
-- them are checked regardless of order.  Pipes expected to stay quiet
-- (dropped frames) are watched after the scenario.
entity tb is
end tb;

architecture arch of tb is

  constant width_list_c : integer_vector(0 to 2) := (1, 2, 4);
  constant block_count_c : natural := 6;

  -- VID 1 is the native VLAN
  constant vlan_id_list_c : vlan_id_vector(0 to 2) := (1, 100, 200);
  constant native_vlan_id_c : vlan_id_t := 1;

  constant da_c : byte_string := from_hex("020000000001");
  constant sa_c : byte_string := from_hex("020000000002");

  constant untagged_frame_c : byte_string
    := da_c & sa_c & from_hex("1234") & from_hex("deadbeef");
  -- Tagged with the native VID
  constant v1_tagged_c : byte_string
    := da_c & sa_c & from_hex("81000001") & from_hex("88b5") & from_hex("0304");
  constant v1_untagged_c : byte_string
    := da_c & sa_c & from_hex("88b5") & from_hex("0304");
  -- VID 100, PCP/DEI zero
  constant v100_tagged_c : byte_string
    := da_c & sa_c & from_hex("81000064") & from_hex("0800") & from_hex("cafe0001");
  constant v100_untagged_c : byte_string
    := da_c & sa_c & from_hex("0800") & from_hex("cafe0001");
  -- VID 200, PCP 7 on input, priority is discarded
  constant v200_tagged_pcp_c : byte_string
    := da_c & sa_c & from_hex("8100e0c8") & from_hex("0806") & from_hex("0102");
  constant v200_tagged_c : byte_string
    := da_c & sa_c & from_hex("810000c8") & from_hex("0806") & from_hex("0102");
  constant v200_untagged_c : byte_string
    := da_c & sa_c & from_hex("0806") & from_hex("0102");
  -- VID 300, not in the configured list
  constant v300_tagged_c : byte_string
    := da_c & sa_c & from_hex("8100012c") & from_hex("0800") & from_hex("aa");

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to width_list_c'length * block_count_c - 1);

  -- Receives one packet, checks its keep pattern and returns its
  -- bytes and reject flag.
  procedure packet_get(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal stream_i: in master_t;
                       signal stream_o: out slave_t;
                       variable rx: inout byte_stream;
                       variable rejected: out boolean;
                       constant what: string)
  is
    variable beat: master_t;
    variable d: byte_string(0 to cfg.data_width-1);
  begin
    clear(rx);
    loop
      receive(cfg, clock, stream_i, stream_o, beat);

      assert is_packed(cfg, beat)
        report what & ": sparse keep pattern on output"
        severity failure;

      d := bytes(cfg, beat);
      for i in 0 to byte_count(cfg, beat) - 1
      loop
        write(rx, d(i));
      end loop;

      if is_last(cfg, beat) then
        rejected := is_rejected(cfg, beat);
        exit;
      end if;
    end loop;
  end procedure;

  procedure packet_expect(constant cfg: config_t;
                          signal clock: in std_ulogic;
                          signal stream_i: in master_t;
                          signal stream_o: out slave_t;
                          constant expected: byte_string;
                          constant rejected: boolean;
                          constant what: string)
  is
    variable rx: byte_stream;
    variable rejected_v: boolean;
  begin
    packet_get(cfg, clock, stream_i, stream_o, rx, rejected_v, what);
    assert rejected_v = rejected
      report what & ": unexpected reject flag state"
      severity failure;
    assert_equal(what, rx.all, expected, failure);
    deallocate(rx);
  end procedure;

  -- Expects as many packets as lengths has entries, each matching one
  -- of the expected packets, in any order.  expected is the
  -- concatenation of the packets, rejected their reject flags.
  procedure packets_expect_any(constant cfg: config_t;
                               signal clock: in std_ulogic;
                               signal stream_i: in master_t;
                               signal stream_o: out slave_t;
                               constant expected: byte_string;
                               constant lengths: integer_vector;
                               constant rejected: std_ulogic_vector;
                               constant what: string)
  is
    alias xp: byte_string(0 to expected'length-1) is expected;
    alias xl: integer_vector(0 to lengths'length-1) is lengths;
    alias xr: std_ulogic_vector(0 to rejected'length-1) is rejected;
    variable matched: std_ulogic_vector(xl'range) := (others => '0');
    variable rx: byte_stream;
    variable rejected_v, found_v: boolean;
    variable offset: natural;
  begin
    for n in xl'range
    loop
      packet_get(cfg, clock, stream_i, stream_o, rx, rejected_v, what);

      found_v := false;
      offset := 0;
      for e in xl'range
      loop
        if matched(e) = '0'
          and rx.all'length = xl(e)
          and rx.all = xp(offset to offset + xl(e) - 1)
          and rejected_v = (xr(e) = '1') then
          matched(e) := '1';
          found_v := true;
          exit;
        end if;
        offset := offset + xl(e);
      end loop;

      assert found_v
        report what & ": unexpected packet " & to_string(rx.all)
        & ", rejected " & to_string(rejected_v)
        severity failure;
    end loop;
    deallocate(rx);
  end procedure;

  -- Keeps the stream accepting for some cycles, nothing may come out.
  procedure expect_idle(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal stream_i: in master_t;
                        signal stream_o: out slave_t;
                        constant cycles: natural;
                        constant what: string)
  is
  begin
    stream_o <= accept(cfg, true);
    for i in 1 to cycles
    loop
      wait until rising_edge(clock);
      assert not is_valid(cfg, stream_i)
        report what & ": unexpected packet"
        severity failure;
    end loop;
    stream_o <= accept(cfg, false);
  end procedure;

begin

  watchdog: process is
    constant all_done_c : std_ulogic_vector(done_s'range) := (others => '1');
  begin
    wait until done_s = all_done_c for 1 ms;
    assert done_s = all_done_c
      report "Timeout, done: " & to_string(done_s)
      severity failure;
    wait;
  end process;

  width_gen: for index in width_list_c'range generate
    constant width_c : natural := width_list_c(index);
    constant cfg_c : config_t := stream_config(width_c);
    constant pad_c : byte_string(0 to ethernet_frame_offset(cfg_c)-1)
      := (others => x"00");
    constant name_c : string := "W" & to_string(width_c);
    constant done_base_c : natural := index * block_count_c;

    -- Frames get the front padding of the mac side frame block
    function f(frame: byte_string) return byte_string
    is
    begin
      return pad_c & frame;
    end function;
  begin

    demux: block
      signal in_s : bus_t;
      signal vlan_m_s : master_vector(0 to 2);
      signal vlan_s_s : slave_vector(0 to 2);
    begin
      gen: process
      begin
        in_s.m <= transfer_defaults(cfg_c);
        wait for 100 ns;
        wait until falling_edge(clock_s);

        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(untagged_frame_c), user => "0");
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v100_tagged_c), user => "0");
        -- Unknown VID, must be dropped
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v300_tagged_c), user => "0");
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v200_tagged_pcp_c), user => "0");
        -- Tagged with the native VID, merged with untagged frames
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v1_tagged_c), user => "0");
        -- Rejected frame, forwarded rejected
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(untagged_frame_c), user => "1");
        in_s.m <= transfer_defaults(cfg_c);
        wait;
      end process;

      -- One checker per pipe: a pipe left unread would hold the
      -- frames queued behind it in the demux.
      native_chk: process
      begin
        done_s(done_base_c + 0) <= '0';
        vlan_s_s(0) <= accept(cfg_c, false);
        wait for 100 ns;

        packets_expect_any(cfg_c, clock_s, vlan_m_s(0), vlan_s_s(0),
                           expected => f(untagged_frame_c)
                           & f(v1_untagged_c)
                           & f(untagged_frame_c),
                           lengths => (f(untagged_frame_c)'length,
                                       f(v1_untagged_c)'length,
                                       f(untagged_frame_c)'length),
                           rejected => "001",
                           what => name_c & " demux native");

        -- VID 300 must not show up
        expect_idle(cfg_c, clock_s, vlan_m_s(0), vlan_s_s(0), 100,
                    name_c & " demux native after");

        log_info(name_c & " demux native OK");
        done_s(done_base_c + 0) <= '1';
        wait;
      end process;

      v100_chk: process
      begin
        done_s(done_base_c + 1) <= '0';
        vlan_s_s(1) <= accept(cfg_c, false);
        wait for 100 ns;

        packet_expect(cfg_c, clock_s, vlan_m_s(1), vlan_s_s(1),
                      f(v100_untagged_c), false, name_c & " demux vid 100");
        expect_idle(cfg_c, clock_s, vlan_m_s(1), vlan_s_s(1), 100,
                    name_c & " demux vid 100 after");

        log_info(name_c & " demux vid 100 OK");
        done_s(done_base_c + 1) <= '1';
        wait;
      end process;

      v200_chk: process
      begin
        done_s(done_base_c + 2) <= '0';
        vlan_s_s(2) <= accept(cfg_c, false);
        wait for 100 ns;

        packet_expect(cfg_c, clock_s, vlan_m_s(2), vlan_s_s(2),
                      f(v200_untagged_c), false, name_c & " demux vid 200");
        expect_idle(cfg_c, clock_s, vlan_m_s(2), vlan_s_s(2), 100,
                    name_c & " demux vid 200 after");

        log_info(name_c & " demux vid 200 OK");
        done_s(done_base_c + 2) <= '1';
        wait;
      end process;

      dut: nsl_inet.stream_vlan.stream_vlan_demux
        generic map(
          config_c => cfg_c,
          vlan_id_c => vlan_id_list_c,
          native_vlan_id_c => native_vlan_id_c
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => in_s.m,
          in_o => in_s.s,

          out_o => vlan_m_s,
          out_i => vlan_s_s
          );
    end block;

    mux: block
      signal out_s : bus_t;
      signal vlan_m_s : master_vector(0 to 2);
      signal vlan_s_s : slave_vector(0 to 2);
    begin
      gen: process
      begin
        vlan_m_s(0) <= transfer_defaults(cfg_c);
        vlan_m_s(1) <= transfer_defaults(cfg_c);
        vlan_m_s(2) <= transfer_defaults(cfg_c);
        wait for 100 ns;
        wait until falling_edge(clock_s);

        packet_send(cfg_c, clock_s, vlan_s_s(0), vlan_m_s(0),
                    packet => f(untagged_frame_c), user => "0");
        vlan_m_s(0) <= transfer_defaults(cfg_c);
        packet_send(cfg_c, clock_s, vlan_s_s(1), vlan_m_s(1),
                    packet => f(v100_untagged_c), user => "0");
        vlan_m_s(1) <= transfer_defaults(cfg_c);
        packet_send(cfg_c, clock_s, vlan_s_s(2), vlan_m_s(2),
                    packet => f(v200_untagged_c), user => "0");
        vlan_m_s(2) <= transfer_defaults(cfg_c);
        wait;
      end process;

      chk: process
      begin
        done_s(done_base_c + 3) <= '0';
        out_s.s <= accept(cfg_c, false);
        wait for 100 ns;

        packet_expect(cfg_c, clock_s, out_s.m, out_s.s,
                      f(untagged_frame_c), false, name_c & " mux native");
        packet_expect(cfg_c, clock_s, out_s.m, out_s.s,
                      f(v100_tagged_c), false, name_c & " mux vid 100");
        packet_expect(cfg_c, clock_s, out_s.m, out_s.s,
                      f(v200_tagged_c), false, name_c & " mux vid 200");

        log_info(name_c & " mux OK");
        done_s(done_base_c + 3) <= '1';
        wait;
      end process;

      dut: nsl_inet.stream_vlan.stream_vlan_mux
        generic map(
          config_c => cfg_c,
          vlan_id_c => vlan_id_list_c,
          native_vlan_id_c => native_vlan_id_c
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => vlan_m_s,
          in_o => vlan_s_s,

          out_o => out_s.m,
          out_i => out_s.s
          );
    end block;

    -- Default native VLAN (0) is not in the VID list: untagged frames
    -- are dropped
    native_absent: block
      signal in_s : bus_t;
      signal vlan_m_s : master_vector(0 to 1);
      signal vlan_s_s : slave_vector(0 to 1);
    begin
      gen: process
      begin
        in_s.m <= transfer_defaults(cfg_c);
        wait for 100 ns;
        wait until falling_edge(clock_s);

        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(untagged_frame_c), user => "0");
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v100_tagged_c), user => "0");
        in_s.m <= transfer_defaults(cfg_c);
        wait;
      end process;

      chk: process
      begin
        done_s(done_base_c + 4) <= '0';
        vlan_s_s(0) <= accept(cfg_c, false);
        vlan_s_s(1) <= accept(cfg_c, false);
        wait for 100 ns;

        packet_expect(cfg_c, clock_s, vlan_m_s(0), vlan_s_s(0),
                      f(v100_untagged_c), false,
                      name_c & " native absent vid 100");

        expect_idle(cfg_c, clock_s, vlan_m_s(0), vlan_s_s(0), 100,
                    name_c & " native absent vid 100 after");
        expect_idle(cfg_c, clock_s, vlan_m_s(1), vlan_s_s(1), 100,
                    name_c & " native absent vid 200");

        log_info(name_c & " native absent OK");
        done_s(done_base_c + 4) <= '1';
        wait;
      end process;

      dut: nsl_inet.stream_vlan.stream_vlan_demux
        generic map(
          config_c => cfg_c,
          vlan_id_c => vlan_id_vector'(100, 200)
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => in_s.m,
          in_o => in_s.s,

          out_o => vlan_m_s,
          out_i => vlan_s_s
          );
    end block;

    loopback: block
      signal in_s, out_s : bus_t;
      signal mid_m_s : master_vector(0 to 2);
      signal mid_s_s : slave_vector(0 to 2);
    begin
      gen: process
      begin
        in_s.m <= transfer_defaults(cfg_c);
        wait for 100 ns;
        wait until falling_edge(clock_s);

        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v100_tagged_c), user => "0");
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(untagged_frame_c), user => "0");
        -- Tagged with native VID, comes back untagged
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v1_tagged_c), user => "0");
        packet_send(cfg_c, clock_s, in_s.s, in_s.m,
                    packet => f(v200_tagged_pcp_c), user => "0");
        in_s.m <= transfer_defaults(cfg_c);
        wait;
      end process;

      chk: process
      begin
        done_s(done_base_c + 5) <= '0';
        out_s.s <= accept(cfg_c, false);
        wait for 100 ns;

        packets_expect_any(cfg_c, clock_s, out_s.m, out_s.s,
                           expected => f(v100_tagged_c)
                           & f(untagged_frame_c)
                           & f(v1_untagged_c)
                           & f(v200_tagged_c),
                           lengths => (f(v100_tagged_c)'length,
                                       f(untagged_frame_c)'length,
                                       f(v1_untagged_c)'length,
                                       f(v200_tagged_c)'length),
                           rejected => "0000",
                           what => name_c & " loopback");

        log_info(name_c & " loopback OK");
        done_s(done_base_c + 5) <= '1';
        wait;
      end process;

      demux: nsl_inet.stream_vlan.stream_vlan_demux
        generic map(
          config_c => cfg_c,
          vlan_id_c => vlan_id_list_c,
          native_vlan_id_c => native_vlan_id_c
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => in_s.m,
          in_o => in_s.s,

          out_o => mid_m_s,
          out_i => mid_s_s
          );

      mux: nsl_inet.stream_vlan.stream_vlan_mux
        generic map(
          config_c => cfg_c,
          vlan_id_c => vlan_id_list_c,
          native_vlan_id_c => native_vlan_id_c
          )
        port map(
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          in_i => mid_m_s,
          in_o => mid_s_s,

          out_o => out_s.m,
          out_i => out_s.s
          );
    end block;
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
