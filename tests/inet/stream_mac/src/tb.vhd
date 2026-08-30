library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.mac.all;

-- Ethernet MAC framing over AXI4-Stream, at 1, 2 and 4 bytes per
-- beat, without forwarded blocks, with one forwarded block whose
-- transported size exceeds its contents, and with two forwarded
-- blocks.
--
-- Each configuration runs the transmitter alone, the receiver alone,
-- both chained back-to-back, and a line-rate phase where minimum-size
-- frames enter the receiver with no interpacket gap and a monitor
-- proves the receiver input never stalls.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 23);

  constant instance_count_c : natural := 6;

  constant da_c : mac48_t := from_hex("0123456789ab");
  constant sa_c : mac48_t := from_hex("fedcba987654");
  constant ethertype_c : ethertype_t := ethertype_ipv4;

  type natural_vector is array(natural range <>) of natural;

  -- Payload lengths spanning the padding threshold and, at the wider
  -- configurations, every possible fill of the last beat, with and
  -- without padding.
  constant payload_length_c : natural_vector(0 to 12)
    := (0, 1, 2, 3, 10, 45, 46, 47, 48, 49, 50, 63, 64);

  constant linerate_count_c : natural := 20;

  function width_of(index: natural) return natural
  is
    constant w_c: natural_vector(0 to instance_count_c-1) := (1, 2, 4, 4, 2, 4);
  begin
    return w_c(index);
  end function;

  -- Contents lengths of the blocks forwarded below the ethernet frame
  -- block.  The 5-byte and 3-byte blocks are shorter than their
  -- transported size at the widths they are used with.
  function header_length_of(index: natural) return integer_vector
  is
  begin
    case index is
      when 3 => return (0 => 5);
      when 4 => return (0 => 5);
      when 5 => return (0 => 5, 1 => 3);
      when others => return null_integer_vector;
    end case;
  end function;

  -- Everything preceding the first ethernet header byte: the
  -- forwarded blocks, contents and tail padding alike, filled with a
  -- recognizable pattern so that verbatim forwarding is checked, then
  -- the front pad of the ethernet frame block, which block producers
  -- leave at zero.
  function prefix_of(index: natural) return byte_string
  is
    constant cfg_c: config_t := stream_config(width_of(index));
    constant block_size_c: natural
      := context_byte_count(cfg_c, header_length_of(index));
    variable ret: byte_string(0 to block_size_c
                              + ethernet_frame_offset(cfg_c) - 1)
      := (others => x"00");
  begin
    for i in 0 to block_size_c-1
    loop
      ret(i) := to_byte(16#a0# + i);
    end loop;
    return ret;
  end function;

  function payload_of(length: natural; seed: natural) return byte_string
  is
    variable ret: byte_string(0 to length-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_byte((seed * 37 + i * 7 + 1) mod 256);
    end loop;
    return ret;
  end function;

  -- Frame as handed to the transmitter and as delivered by the
  -- receiver, before padding.
  function frame_of(length: natural; seed: natural) return byte_string
  is
  begin
    return da_c & sa_c & to_be(to_unsigned(ethertype_c, 16))
      & payload_of(length, seed);
  end function;

  -- Length the transmitter pads the frame to, FCS excluded: at least
  -- the ethernet minimum, and enough more for the frame, whose first
  -- header byte sits after the front pad, to end on a beat boundary.
  function padded_length_of(index: natural; length: natural) return natural
  is
    constant w_c: natural := width_of(index);
    constant offset_c: natural := ethernet_frame_offset(stream_config(w_c));
    variable ret: natural := ethernet_header_length_c + length;
  begin
    if ret < 60 then
      ret := 60;
    end if;
    while (ret + offset_c) mod w_c /= 0
    loop
      ret := ret + 1;
    end loop;
    return ret;
  end function;

  -- Frame as seen on the wire, padded, FCS included.
  function wire_frame_of(index: natural;
                         length: natural; seed: natural) return byte_string
  is
    constant packed_c: byte_string
      := frame_pack(da_c, sa_c, ethertype_c, payload_of(length, seed),
                    padded_length_of(index, length) + 4);
    constant ret: byte_string(0 to packed_c'length-1) := packed_c;
  begin
    return ret;
  end function;

  -- Frame as delivered by the receiver: padded, FCS stripped.
  function padded_frame_of(index: natural;
                           length: natural; seed: natural) return byte_string
  is
    constant wire_c: byte_string := wire_frame_of(index, length, seed);
    constant ret: byte_string(0 to wire_c'length-5) := wire_c(0 to wire_c'length-5);
  begin
    return ret;
  end function;

  -- A frame shorter than the minimum ethernet frame size, carrying a
  -- valid FCS: only the size rule may reject it.
  constant runt_data_c : byte_string(0 to 35) := payload_of(36, 77);
  constant runt_wire_c : byte_string(0 to 39)
    := runt_data_c
    & crc_spill(fcs_params_c,
                crc_update(fcs_params_c, crc_init(fcs_params_c), runt_data_c));

  function corrupted(frame: byte_string; index: natural) return byte_string
  is
    variable ret: byte_string(0 to frame'length-1) := frame;
  begin
    ret(index) := ret(index) xor x"55";
    return ret;
  end function;

  procedure packet_expect(constant cfg: config_t;
                          signal clock: in std_ulogic;
                          signal stream_i: in master_t;
                          signal stream_o: out slave_t;
                          constant expected: byte_string;
                          constant rejected: boolean;
                          constant what: string)
  is
    variable beat: master_t;
    variable rx: byte_stream;
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
        assert is_rejected(cfg, beat) = rejected
          report what & ": unexpected reject flag state"
          severity failure;
        exit;
      end if;
    end loop;

    assert_equal(what, rx.all, expected, failure);
    deallocate(rx);
  end procedure;

begin

  geometry: process is
  begin
    assert_equal("W1 frame offset",
                 ethernet_frame_offset(stream_config(1)), 0, failure);
    assert_equal("W2 frame offset",
                 ethernet_frame_offset(stream_config(2)), 0, failure);
    assert_equal("W4 frame offset",
                 ethernet_frame_offset(stream_config(4)), 2, failure);
    wait;
  end process;

  instance: for index in 0 to instance_count_c-1 generate
    constant width_c : natural := width_of(index);
    constant lengths_c : integer_vector := header_length_of(index);
    constant pre_c : byte_string := prefix_of(index);
    constant cfg_c : config_t := stream_config(width_c);
    constant name_c : string := "W" & to_string(width_c)
                                & "P" & to_string(pre_c'length);

    signal tx_in_s, tx_out_s : bus_t;
    signal rx_in_s, rx_out_s : bus_t;
    signal loop_in_s, loop_mid_s, loop_out_s : bus_t;
    signal line_in_s, line_out_s : bus_t;
  begin

    tx_stim: process is
    begin
      tx_in_s.m <= transfer_defaults(cfg_c);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_send(cfg_c, clock_s, tx_in_s.s, tx_in_s.m,
                    packet => pre_c & frame_of(payload_length_c(i), i),
                    user => "0");
      end loop;
      wait;
    end process;

    tx_check: process is
    begin
      tx_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_expect(cfg_c, clock_s, tx_out_s.m, tx_out_s.s,
                      expected => pre_c & wire_frame_of(index, payload_length_c(i), i),
                      rejected => false,
                      what => name_c & " tx payload "
                      & to_string(payload_length_c(i)));
      end loop;

      log_info(name_c & " transmitter OK");
      done_s(index * 4) <= '1';
      wait;
    end process;

    rx_stim: process is
    begin
      rx_in_s.m <= transfer_defaults(cfg_c);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_send(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
                    packet => pre_c & wire_frame_of(index, payload_length_c(i), i),
                    user => "0");
      end loop;

      packet_send(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
                  packet => pre_c & corrupted(wire_frame_of(index, 50, 8), 20),
                  user => "0");

      packet_send(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
                  packet => pre_c & runt_wire_c,
                  user => "0");

      packet_send(cfg_c, clock_s, rx_in_s.s, rx_in_s.m,
                  packet => pre_c & wire_frame_of(index, 10, 4),
                  user => "1");
      wait;
    end process;

    rx_check: process is
    begin
      rx_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_expect(cfg_c, clock_s, rx_out_s.m, rx_out_s.s,
                      expected => pre_c & padded_frame_of(index, payload_length_c(i), i),
                      rejected => false,
                      what => name_c & " rx payload "
                      & to_string(payload_length_c(i)));
      end loop;

      packet_expect(cfg_c, clock_s, rx_out_s.m, rx_out_s.s,
                    expected => pre_c
                    & corrupted(padded_frame_of(index, 50, 8), 20),
                    rejected => true,
                    what => name_c & " rx corrupted");

      packet_expect(cfg_c, clock_s, rx_out_s.m, rx_out_s.s,
                    expected => pre_c & runt_data_c,
                    rejected => true,
                    what => name_c & " rx runt");

      packet_expect(cfg_c, clock_s, rx_out_s.m, rx_out_s.s,
                    expected => pre_c & padded_frame_of(index, 10, 4),
                    rejected => true,
                    what => name_c & " rx already rejected");

      log_info(name_c & " receiver OK");
      done_s(index * 4 + 1) <= '1';
      wait;
    end process;

    loop_stim: process is
    begin
      loop_in_s.m <= transfer_defaults(cfg_c);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_send(cfg_c, clock_s, loop_in_s.s, loop_in_s.m,
                    packet => pre_c & frame_of(payload_length_c(i), i + 3),
                    user => "0");
      end loop;

      packet_send(cfg_c, clock_s, loop_in_s.s, loop_in_s.m,
                  packet => pre_c & frame_of(20, 5),
                  user => "1");
      wait;
    end process;

    loop_check: process is
    begin
      loop_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for i in payload_length_c'range
      loop
        packet_expect(cfg_c, clock_s, loop_out_s.m, loop_out_s.s,
                      expected => pre_c
                      & padded_frame_of(index, payload_length_c(i), i + 3),
                      rejected => false,
                      what => name_c & " loopback payload "
                      & to_string(payload_length_c(i)));
      end loop;

      packet_expect(cfg_c, clock_s, loop_out_s.m, loop_out_s.s,
                    expected => pre_c & padded_frame_of(index, 20, 5),
                    rejected => true,
                    what => name_c & " loopback rejected");

      log_info(name_c & " loopback OK");
      done_s(index * 4 + 2) <= '1';
      wait;
    end process;

    line_stim: process is
    begin
      line_in_s.m <= transfer_defaults(cfg_c);
      wait for 100 ns;

      for i in 0 to linerate_count_c-1
      loop
        packet_send(cfg_c, clock_s, line_in_s.s, line_in_s.m,
                    packet => pre_c & wire_frame_of(index, 0, i),
                    user => "0");
      end loop;
      wait;
    end process;

    line_check: process is
    begin
      line_out_s.s <= accept(cfg_c, false);
      wait for 40 ns;

      for i in 0 to linerate_count_c-1
      loop
        packet_expect(cfg_c, clock_s, line_out_s.m, line_out_s.s,
                      expected => pre_c & padded_frame_of(index, 0, i),
                      rejected => false,
                      what => name_c & " line rate frame " & to_string(i));
      end loop;

      log_info(name_c & " line rate OK");
      done_s(index * 4 + 3) <= '1';
      wait;
    end process;

    transmitter: nsl_inet.stream_mac.stream_mac_transmitter
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => tx_in_s.m,
        in_o => tx_in_s.s,

        out_o => tx_out_s.m,
        out_i => tx_out_s.s
        );

    receiver: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => rx_in_s.m,
        in_o => rx_in_s.s,

        out_o => rx_out_s.m,
        out_i => rx_out_s.s
        );

    loop_transmitter: nsl_inet.stream_mac.stream_mac_transmitter
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => loop_in_s.m,
        in_o => loop_in_s.s,

        out_o => loop_mid_s.m,
        out_i => loop_mid_s.s
        );

    loop_receiver: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => loop_mid_s.m,
        in_o => loop_mid_s.s,

        out_o => loop_out_s.m,
        out_i => loop_out_s.s
        );

    line_receiver: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => lengths_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => line_in_s.m,
        in_o => line_in_s.s,

        out_o => line_out_s.m,
        out_i => line_out_s.s
        );

    line_monitor: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => name_c & " line rate input",
        grace_cycles_c => 4
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => line_in_s
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
