library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.mac.all;
use nsl_inet.vlan.all;
use nsl_inet.stream_vlan.all;

-- Stream VLAN demux and mux test.
--
-- One demux and one mux per (stream width, forwarded block list,
-- VID list, native VID) combination: every width without forwarded
-- block, padded forwarded blocks at widths 2 and 4, instances with and
-- without a native VLAN, and one instance whose only pipe is the
-- native one.
--
-- The demux phase feeds frames tagged with configured VIDs, with an
-- unconfigured VID, with priority bits set, untagged frames, rejected
-- frames, a short frame, then a burst of minimum-size frames at line
-- rate with a backpressure monitor armed on the demux input.  Each
-- pipe checks it gets exactly its frames, untagged, with the forwarded
-- blocks and the reject flag preserved.  The native pipe accepts its
-- frames in any order, untagged and native-tagged frames taking
-- distinct paths.
--
-- The mux phase sends one packet at a time on every pipe in turn, one
-- of them rejected, and checks it leaves tagged with the pipe VID, or
-- untouched for the native pipe.
entity tb is
end tb;

architecture arch of tb is

  constant instance_count_c : natural := 6;
  constant width_list_c : integer_vector(0 to instance_count_c-1)
    := (1, 2, 4, 4, 2, 4);
  constant block_list_c : integer_vector(0 to instance_count_c-1)
    := (0, 0, 0, 5, 5, 0);
  constant native_list_c : integer_vector(0 to instance_count_c-1)
    := (0, 30, 30, 0, 20, 30);

  constant max_pipe_count_c : natural := 3;
  -- Per instance: one slot per pipe checker, one for the mux checker
  constant slot_count_c : natural := max_pipe_count_c + 1;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to instance_count_c * slot_count_c - 1);

  constant da_c : mac48_t := from_hex("020000000001");
  constant sa_c : mac48_t := from_hex("020000000002");

  function instance_vids(inst: integer) return vlan_id_vector
  is
  begin
    if inst = 5 then
      return vlan_id_vector'(0 => 30);
    end if;
    return vlan_id_vector'(10, 20, 30);
  end function;

  function block_lengths(length: integer) return integer_vector
  is
  begin
    if length = 0 then
      return null_integer_vector;
    else
      return integer_vector'(0 => length);
    end if;
  end function;

  constant directed_count_c : natural := 8;
  constant linerate_count_c : natural := 16;
  constant rx_count_c : natural := directed_count_c + linerate_count_c;
  constant max_payload_c : natural := 60;

  -- VID of a received frame, -1 for an untagged frame
  function rx_vid(idx: integer) return integer
  is
  begin
    case idx is
      when 0 => return 10;
      when 1 => return 20;
      when 2 => return -1;
      when 3 => return 99;
      when 4 => return 30;
      when 5 => return 10;
      when 6 => return -1;
      when 7 => return 20;
      when others =>
        case idx mod 4 is
          when 0 => return 10;
          when 1 => return 20;
          when 2 => return 30;
          when others => return -1;
        end case;
    end case;
  end function;

  -- PCP and DEI bits, to be ignored by the VID lookup
  function rx_priority(idx: integer) return natural
  is
  begin
    if idx = 5 then
      return 16#f#;
    end if;
    return 0;
  end function;

  function rx_rejected(idx: integer) return boolean
  is
  begin
    return idx = 4 or idx = 6;
  end function;

  function rx_payload_length(idx: integer) return natural
  is
  begin
    case idx is
      when 0 => return max_payload_c;
      when 7 => return 4;
      when others => return 46;
    end case;
  end function;

  function rx_payload(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to rx_payload_length(idx)-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 13 + k * 7 + 5) mod 256);
    end loop;
    return ret;
  end function;

  function rx_ethertype(idx: integer) return byte_string
  is
  begin
    return to_be(to_unsigned(16#88b5# + idx, 16));
  end function;

  function rx_tag(idx: integer) return byte_string
  is
  begin
    if rx_vid(idx) < 0 then
      return null_byte_string;
    end if;
    return to_be(to_unsigned(ethertype_vlan, 16))
      & to_be(to_unsigned(rx_priority(idx) * 4096 + rx_vid(idx), 16));
  end function;

  constant tx_count_c : natural := 7;

  function tx_rejected(idx: integer) return boolean
  is
  begin
    return idx = 4;
  end function;

  function tx_payload(idx: integer) return byte_string
  is
    variable ret: byte_string(0 to 20 + idx * 5 - 1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 31 + k * 3 + 17) mod 256);
    end loop;
    return ret;
  end function;

  function tx_ethertype(idx: integer) return byte_string
  is
  begin
    return to_be(to_unsigned(16#0800# + idx, 16));
  end function;

begin

  watchdog: process is
    constant all_done_c : std_ulogic_vector(done_s'range) := (others => '1');
  begin
    wait until done_s = all_done_c for 2 ms;
    assert done_s = all_done_c
      report "Timeout, done: " & to_string(done_s)
      severity failure;
    wait;
  end process;

  inst_gen: for inst in 0 to instance_count_c-1 generate
    constant width_c : natural := width_list_c(inst);
    constant cfg_c : config_t := stream_config(width_c);
    constant lengths_c : integer_vector := block_lengths(block_list_c(inst));
    constant vids_c : vlan_id_vector := instance_vids(inst);
    constant pipe_count_c : natural := vids_c'length;
    constant native_c : vlan_id_t := native_list_c(inst);
    constant native_index_c : integer := vlan_index(vids_c, native_c);
    constant pre_c : natural := context_byte_count(cfg_c, lengths_c);
    constant frame_off_c : natural := ethernet_frame_offset(cfg_c);
    constant frame_pad_c : byte_string(0 to frame_off_c-1) := (others => x"00");
    constant ipg_beats_c : natural := 20 / width_c;
    constant name_c : string := "inst " & to_string(inst)
      & " W" & to_string(width_c) & " B" & to_string(pre_c);

    function pre_pattern return byte_string
    is
      variable ret: byte_string(0 to pre_c-1);
    begin
      for k in ret'range
      loop
        ret(k) := to_byte((k * 37 + 16#a5#) mod 256);
      end loop;
      return ret;
    end function;

    constant pre_pat_c : byte_string(0 to pre_c-1) := pre_pattern;

    -- Pipe a received frame is expected on, -1 if dropped
    function rx_pipe(idx: integer) return integer
    is
    begin
      if rx_vid(idx) < 0 then
        return native_index_c;
      end if;
      return vlan_index(vids_c, rx_vid(idx));
    end function;

    function rx_wire(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & frame_pad_c & da_c & sa_c
        & rx_tag(idx) & rx_ethertype(idx) & rx_payload(idx);
    end function;

    function rx_expected(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & frame_pad_c & da_c & sa_c
        & rx_ethertype(idx) & rx_payload(idx);
    end function;

    function tx_pipe(idx: integer) return natural
    is
    begin
      return idx mod pipe_count_c;
    end function;

    function tx_packet(idx: integer) return byte_string
    is
    begin
      return pre_pat_c & frame_pad_c & da_c & sa_c
        & tx_ethertype(idx) & tx_payload(idx);
    end function;

    function tx_expected(idx: integer) return byte_string
    is
      constant vid_c : vlan_id_t := vids_c(vids_c'left + tx_pipe(idx));
    begin
      if tx_pipe(idx) = native_index_c then
        return tx_packet(idx);
      end if;
      return pre_pat_c & frame_pad_c & da_c & sa_c
        & to_be(to_unsigned(ethertype_vlan, 16))
        & to_be(to_unsigned(vid_c, 16))
        & tx_ethertype(idx) & tx_payload(idx);
    end function;

    procedure frame_send(signal m: out master_t;
                         signal s: in slave_t;
                         constant frame: byte_string;
                         constant rejected: boolean)
    is
      alias f: byte_string(0 to frame'length-1) is frame;
      variable beats_v, first_v, nbytes_v: integer;
      variable chunk_v: byte_string(0 to width_c-1);
      variable keep_v: std_ulogic_vector(0 to width_c-1);
      variable user_v: std_ulogic_vector(0 to 0);
    begin
      beats_v := (f'length + width_c - 1) / width_c;

      for b in 0 to beats_v-1
      loop
        first_v := b * width_c;
        nbytes_v := width_c;
        if first_v + nbytes_v > f'length then
          nbytes_v := f'length - first_v;
        end if;

        chunk_v := (others => x"00");
        keep_v := (others => '0');
        for k in 0 to nbytes_v-1
        loop
          chunk_v(k) := f(first_v + k);
          keep_v(k) := '1';
        end loop;

        user_v := "0";
        if b = beats_v-1 and rejected then
          user_v := "1";
        end if;

        m <= transfer(cfg_c,
                      bytes => chunk_v,
                      keep => keep_v,
                      user => user_v,
                      valid => true,
                      last => b = beats_v-1);
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(cfg_c, s);
        end loop;
        wait until falling_edge(clock_s);
      end loop;

      m <= transfer_defaults(cfg_c);
    end procedure;

    procedure frame_receive(constant context: string;
                            signal m: in master_t;
                            signal s: out slave_t;
                            variable frame: inout byte_stream;
                            variable rejected: out boolean)
    is
      variable beat_v: master_t;
      variable data_v: byte_string(0 to width_c-1);
    begin
      clear(frame);
      loop
        receive(cfg_c, clock_s, m, s, beat_v);

        assert is_packed(cfg_c, beat_v)
          report context & ": sparse keep pattern"
          severity failure;

        data_v := bytes(cfg_c, beat_v);
        for i in 0 to byte_count(cfg_c, beat_v)-1
        loop
          write(frame, data_v(i));
        end loop;

        if is_last(cfg_c, beat_v) then
          rejected := is_rejected(cfg_c, beat_v);
          exit;
        end if;
      end loop;
    end procedure;

    signal demux_in_s, mux_out_s : bus_t;
    signal demux_out_m_s, mux_in_m_s : master_vector(0 to pipe_count_c-1);
    signal demux_out_s_s, mux_in_s_s : slave_vector(0 to pipe_count_c-1);

    signal monitor_en_s : std_ulogic;
    signal tx_checked_s : natural := 0;

  begin

    unused_slots: for p in pipe_count_c to max_pipe_count_c-1
    generate
      done_s(inst * slot_count_c + p) <= '1';
    end generate;

    demux_stim: process is
    begin
      demux_in_s.m <= transfer_defaults(cfg_c);
      monitor_en_s <= '1';
      wait for 200 ns;
      wait until falling_edge(clock_s);

      for idx in 0 to rx_count_c-1
      loop
        frame_send(demux_in_s.m, demux_in_s.s, rx_wire(idx), rx_rejected(idx));
        for i in 1 to ipg_beats_c
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;

      monitor_en_s <= '0';
      wait;
    end process;

    pipe_gen: for p in 0 to pipe_count_c-1 generate
    begin
      pipe_check: process is
        variable frame_v: byte_stream;
        variable rejected_v: boolean;
        variable expected_v: integer_vector(0 to rx_count_c-1);
        variable matched_v: boolean;
        variable count_v, next_v: natural;
      begin
        demux_out_s_s(p) <= accept(cfg_c, false);

        count_v := 0;
        for idx in 0 to rx_count_c-1
        loop
          if rx_pipe(idx) = p then
            expected_v(count_v) := idx;
            count_v := count_v + 1;
          end if;
        end loop;

        wait for 40 ns;

        next_v := 0;
        for n in 0 to count_v-1
        loop
          frame_receive(name_c & " pipe " & to_string(p),
                        demux_out_m_s(p), demux_out_s_s(p),
                        frame_v, rejected_v);

          matched_v := false;
          for e in next_v to count_v-1
          loop
            if expected_v(e) >= 0
              and frame_v.all = rx_expected(expected_v(e))
              and rejected_v = rx_rejected(expected_v(e)) then
              expected_v(e) := -1;
              matched_v := true;
              exit;
            end if;

            -- Only the native pipe may see frames out of order
            exit when p /= native_index_c;
          end loop;

          if not matched_v then
            log_error(name_c & " pipe " & to_string(p)
                      & " frame " & to_string(n) & ": unexpected "
                      & to_string(frame_v.all)
                      & " reject " & to_string(rejected_v));
            if expected_v(next_v) >= 0 then
              log_error("  expected " & to_string(rx_expected(expected_v(next_v)))
                        & " reject " & to_string(rx_rejected(expected_v(next_v))));
            end if;
            assert false severity failure;
          end if;

          while next_v < count_v and expected_v(next_v) < 0
          loop
            next_v := next_v + 1;
          end loop;
        end loop;

        deallocate(frame_v);
        log_info(name_c & " pipe " & to_string(p) & ": "
                 & to_string(count_v) & " frames OK");
        done_s(inst * slot_count_c + p) <= '1';
        wait;
      end process;
    end generate;

    -- One packet at a time, each pipe sending its own once the
    -- previous one got out, so that the output order is the sending
    -- order.
    mux_stim_gen: for p in 0 to pipe_count_c-1 generate
    begin
      mux_stim: process is
      begin
        mux_in_m_s(p) <= transfer_defaults(cfg_c);
        wait for 200 ns;

        for idx in 0 to tx_count_c-1
        loop
          if tx_pipe(idx) = p then
            if tx_checked_s /= idx then
              wait until tx_checked_s = idx;
            end if;
            wait until falling_edge(clock_s);
            frame_send(mux_in_m_s(p), mux_in_s_s(p),
                       tx_packet(idx), tx_rejected(idx));
          end if;
        end loop;
        wait;
      end process;
    end generate;

    mux_check: process is
      variable frame_v: byte_stream;
      variable rejected_v: boolean;
    begin
      mux_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for idx in 0 to tx_count_c-1
      loop
        frame_receive(name_c & " mux", mux_out_s.m, mux_out_s.s,
                      frame_v, rejected_v);

        assert_equal(name_c & " mux packet " & to_string(idx),
                     frame_v.all, tx_expected(idx), failure);
        assert rejected_v = tx_rejected(idx)
          report name_c & " mux packet " & to_string(idx)
          & ": unexpected reject flag state"
          severity failure;

        tx_checked_s <= idx + 1;
      end loop;

      deallocate(frame_v);
      log_info(name_c & " mux: " & to_string(tx_count_c) & " packets OK");
      done_s(inst * slot_count_c + max_pipe_count_c) <= '1';
      wait;
    end process;

    monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "VLAN_DEMUX_" & to_string(inst),
        grace_cycles_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        enable_i => monitor_en_s,
        bus_i => demux_in_s
        );

    demux: nsl_inet.stream_vlan.stream_vlan_demux
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c,
        vlan_id_c => vids_c,
        native_vlan_id_c => native_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => demux_in_s.m,
        in_o => demux_in_s.s,

        out_o => demux_out_m_s,
        out_i => demux_out_s_s
        );

    mux: nsl_inet.stream_vlan.stream_vlan_mux
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c,
        vlan_id_c => vids_c,
        native_vlan_id_c => native_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => mux_in_m_s,
        in_o => mux_in_s_s,

        out_o => mux_out_s.m,
        out_i => mux_out_s.s
        );
  end generate;

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
