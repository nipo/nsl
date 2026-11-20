library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_bnoc, nsl_inet, nsl_usb, nsl_math, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_logic.bool.all;
use nsl_usb.ncm.all;

-- nsl_usb.ncm: receiver, transmitter and loopback for every pair of NTB
-- stream width (1, 2) and frame stream width (1, 2, 4), then the bnoc
-- wrappers in loopback. Every output stalls at random. Frame streams
-- follow nsl_inet.stream: the front pad at width 4, the reject flag
-- driven on every last beat.
--
-- Receiver input: NTB16 blocks laid out as Linux cdc_ncm builds them
-- (NDP right after the NTH16 with room for 40 entries, datagrams 2 bytes
-- past a 4-byte boundary, blocks over tx_max - 3 * 512 padded to 16 KiB,
-- odd lengths), plus the NDP last, datagrams at odd offsets, garbage
-- before a block, a bad NDP and an out-of-range datagram entry.
entity tb is
end tb;

architecture arch of tb is

  constant config_count_c : natural := 6;
  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to config_count_c * 3);

  constant ntb_max_c : natural := 16384;
  subtype buffer_t is byte_string(0 to ntb_max_c + 63);

  constant length_table_c : integer_vector(0 to 9)
    := (14, 15, 60, 61, 64, 511, 512, 513, 1513, 1514);

  -- Receiver cases
  type rx_case_t is
  record
    count : natural;
    ndp_first : boolean;
    remainder : natural;   -- datagram offset modulo 4
    extra : natural;       -- padding bytes after the NDP
    pad_full : boolean;    -- padded to ntb_max_c
    garbage : boolean;     -- 3 words of garbage before the block
    bad_ndp : boolean;     -- NDP signature broken: no datagram delivered
    bad_entry : boolean;   -- an entry out of the block after the first one
  end record;
  type rx_case_vector is array(natural range <>) of rx_case_t;

  constant rx_cases_c : rx_case_vector(0 to 10) := (
    0 => (1, true, 2, 0, false, false, false, false),
    1 => (5, true, 2, 0, false, false, false, false),
    2 => (5, false, 0, 0, false, false, false, false),
    3 => (3, true, 2, 1, false, false, false, false),
    4 => (10, true, 2, 0, true, false, false, false),
    5 => (40, true, 2, 0, false, false, false, false),
    6 => (2, true, 2, 0, false, true, false, false),
    7 => (2, true, 2, 0, false, false, true, false),
    8 => (3, true, 2, 0, false, false, false, true),
    9 => (4, true, 1, 0, false, false, false, false),
    10 => (1, false, 0, 0, false, false, false, false)
    );

  function rx_length(c, i : natural) return natural
  is
  begin
    case c is
      when 4 => return 1514;
      when 5 => return 64;
      when 10 => return 14;
      when others => return length_table_c((c * 7 + i * 3) mod 10);
    end case;
  end function;

  function frame_of(length, seed : natural) return byte_string
  is
    variable ret : byte_string(0 to length-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_byte((seed * 37 + i * 11 + 5) mod 256);
    end loop;
    return ret;
  end function;

  procedure put16(variable b : inout buffer_t; at : natural; v : natural) is
    variable u : unsigned(15 downto 0) := to_unsigned(v, 16);
  begin
    b(at) := std_ulogic_vector(u(7 downto 0));
    b(at + 1) := std_ulogic_vector(u(15 downto 8));
  end procedure;

  function get16(b : buffer_t; at : natural) return natural
  is
  begin
    return to_integer(unsigned(b(at + 1)) & unsigned(b(at)));
  end function;

  -- One receiver case as an NTB16 block.
  procedure ntb_build(variable b : inout buffer_t;
                      variable length : out natural;
                      constant c : natural;
                      constant seq : natural) is
    constant k : rx_case_t := rx_cases_c(c);
    constant ndp_room_c : natural := 8 + 41 * 4;
    variable at, ndp, entries : natural;
    variable index : integer_vector(0 to 40);
    variable len : integer_vector(0 to 40);
  begin
    b := (others => x"00");
    at := 12;
    ndp := 0;
    if k.ndp_first then
      ndp := at;
      at := at + ndp_room_c;
    end if;
    for i in 0 to k.count-1
    loop
      while at mod 4 /= k.remainder loop
        at := at + 1;
      end loop;
      index(i) := at;
      len(i) := rx_length(c, i);
      b(at to at + len(i) - 1) := frame_of(len(i), c * 64 + i);
      at := at + len(i);
    end loop;
    if not k.ndp_first then
      while at mod 4 /= 0 loop
        at := at + 1;
      end loop;
      ndp := at;
      at := at + ndp_room_c;
    end if;

    -- NDP16
    entries := k.count;
    if k.bad_ndp then
      b(ndp to ndp + 3) := (x"4e", x"43", x"4d", x"31");
    else
      b(ndp to ndp + 3) := ncm_ndp16_signature_c;
    end if;
    if k.bad_entry then
      put16(b, ndp + 4, 8 + (entries + 2) * 4);
    else
      put16(b, ndp + 4, 8 + (entries + 1) * 4);
    end if;
    put16(b, ndp + 6, 0);
    for i in 0 to k.count-1
    loop
      if k.bad_entry and i = 1 then
        put16(b, ndp + 8 + 4 * i, at + 100);
        put16(b, ndp + 10 + 4 * i, 60);
        put16(b, ndp + 12 + 4 * i, index(i));
        put16(b, ndp + 14 + 4 * i, len(i));
      elsif k.bad_entry and i > 1 then
        put16(b, ndp + 12 + 4 * i, index(i));
        put16(b, ndp + 14 + 4 * i, len(i));
      else
        put16(b, ndp + 8 + 4 * i, index(i));
        put16(b, ndp + 10 + 4 * i, len(i));
      end if;
    end loop;

    at := at + k.extra;
    if k.pad_full then
      at := ntb_max_c;
    end if;

    b(0 to 3) := ncm_nth16_signature_c;
    put16(b, 4, 12);
    put16(b, 6, seq);
    put16(b, 8, at);
    put16(b, 10, ndp);
    length := at;
  end procedure;

  -- Pseudo random stalls
  procedure stall(variable state : inout natural;
                  signal clock : in std_ulogic;
                  constant max : natural) is
  begin
    state := (state * 75 + 74) mod 65537;
    for i in 1 to state mod (max + 1)
    loop
      wait until rising_edge(clock);
    end loop;
  end procedure;

  -- Sends bytes in beats of the stream width; at width 2 an odd count
  -- ends with keep "10" if the stream has keep, with a padding byte
  -- otherwise (NTB on a 16-bit bus).
  procedure bytes_send(constant cfg : config_t;
                       signal clock : in std_ulogic;
                       signal s : in slave_t;
                       signal m : out master_t;
                       constant data : byte_string;
                       constant user : std_ulogic_vector;
                       variable state : inout natural) is
    alias d : byte_string(0 to data'length-1) is data;
    constant w : natural := cfg.data_width;
    variable bytes_v : byte_string(0 to w-1);
    variable keep_v : std_ulogic_vector(0 to w-1);
    variable at : natural := 0;
  begin
    while at < d'length
    loop
      bytes_v := (others => x"00");
      keep_v := (others => '0');
      for i in 0 to w-1
      loop
        if at + i < d'length then
          bytes_v(i) := d(at + i);
          keep_v(i) := '1';
        end if;
      end loop;
      at := at + w;
      if cfg.has_keep then
        m <= transfer(cfg, bytes => bytes_v, keep => keep_v,
                      user => user, valid => true, last => at >= d'length);
      else
        m <= transfer(cfg, bytes => bytes_v, user => user,
                      valid => true, last => at >= d'length);
      end if;
      loop
        wait until rising_edge(clock);
        exit when is_ready(cfg, s);
      end loop;
      m <= transfer_defaults(cfg);
      stall(state, clock, 2);
    end loop;
  end procedure;

  -- Receives one packet (until last) with random ready.
  procedure packet_get(constant cfg : config_t;
                       signal clock : in std_ulogic;
                       signal m : in master_t;
                       signal s : out slave_t;
                       variable b : inout buffer_t;
                       variable length : out natural;
                       variable rejected : out boolean;
                       variable state : inout natural) is
    variable at : natural := 0;
    variable d : byte_string(0 to cfg.data_width-1);
    variable n : natural;
  begin
    rejected := false;
    loop
      state := (state * 75 + 74) mod 65537;
      s <= accept(cfg, state mod 4 /= 0);
      wait until rising_edge(clock);
      if is_valid(cfg, m) and state mod 4 /= 0 then
        d := bytes(cfg, m);
        n := byte_count(cfg, m);
        assert n = cfg.data_width or is_last(cfg, m)
          report "partial beat before the last one" severity failure;
        b(at to at + n - 1) := d(0 to n - 1);
        at := at + n;
        if is_last(cfg, m) then
          if cfg.user_width >= 1 then
            assert user(cfg, m)(0) = '0' or user(cfg, m)(0) = '1'
              report "reject flag not driven on the last beat" severity failure;
            rejected := user(cfg, m)(0) = '1';
          end if;
          exit;
        end if;
      end if;
    end loop;
    s <= accept(cfg, false);
    length := at;
  end procedure;

  procedure check_bytes(constant what : string;
                        constant got : byte_string;
                        constant want : byte_string) is
  begin
    assert got'length = want'length
      report what & ": " & to_string(got'length) & " bytes, want "
      & to_string(want'length) severity failure;
    assert got = want
      report what & ": contents differ" severity failure;
  end procedure;

  procedure check_count(constant what : string;
                        constant got : unsigned;
                        constant want : natural) is
  begin
    assert to_integer(got) = want
      report what & ": " & to_string(to_integer(got)) & ", want "
      & to_string(want) severity failure;
  end procedure;

  -- Transmitter frames: lengths, with one too short (dropped) and one
  -- rejected (dropped when the frame stream has a user bit)
  constant tx_count_c : natural := 50;

  function tx_length(i : natural) return natural
  is
  begin
    if i = 7 then
      return 10;
    end if;
    return length_table_c((i * 3 + 1) mod 10);
  end function;

  function tx_rejected(i : natural) return boolean
  is
  begin
    return i = 23;
  end function;

  type width_vector is array(natural range <>) of natural;
  constant ntb_width_c : width_vector(0 to config_count_c-1) := (2, 1, 2, 1, 2, 1);
  constant frame_width_c : width_vector(0 to config_count_c-1) := (2, 1, 1, 2, 4, 4);

  -- nsl_inet.stream_mac front pad of a frame at a stream width
  function front_pad(w : natural) return byte_string
  is
    constant n_c : natural := (w - 14 mod w) mod w;
    constant ret_c : byte_string(0 to n_c-1) := (others => x"00");
  begin
    return ret_c;
  end function;

begin

  configs: for index in 0 to config_count_c-1 generate
    constant ntb_cfg_c : config_t := config(ntb_width_c(index), last => true);
    constant frame_cfg_c : config_t := nsl_inet.stream.stream_config(frame_width_c(index));
    constant name_c : string := "N" & to_string(ntb_width_c(index))
                                & "F" & to_string(frame_width_c(index));
    constant pad_c : byte_string := front_pad(frame_width_c(index));
    signal rx_ntb_s, rx_frame_s : bus_t;
    signal tx_frame_s, tx_ntb_s : bus_t;
    signal loop_in_s, loop_mid_s, loop_out_s : bus_t;
    signal rx_stats_s, loop_rx_stats_s : ncm_receiver_stats_t;
    signal tx_stats_s, loop_tx_stats_s : ncm_transmitter_stats_t;
  begin

    rx_stim: process is
      variable b : buffer_t;
      variable n, state : natural := index + 1;
      variable seq : natural := 0;
    begin
      rx_ntb_s.m <= transfer_defaults(ntb_cfg_c);
      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);
      for c in rx_cases_c'range
      loop
        if rx_cases_c(c).garbage then
          bytes_send(ntb_cfg_c, clock_s, rx_ntb_s.s, rx_ntb_s.m,
                     (x"11", x"22", x"33", x"44", x"55", x"66"), "", state);
        end if;
        ntb_build(b, n, c, seq);
        seq := seq + 1;
        bytes_send(ntb_cfg_c, clock_s, rx_ntb_s.s, rx_ntb_s.m,
                   b(0 to n - 1), "", state);
      end loop;
      wait;
    end process;

    rx_check: process is
      variable b : buffer_t;
      variable n, state : natural := index + 11;
      variable rej : boolean;
      variable delivered : natural := 0;
    begin
      rx_frame_s.s <= accept(frame_cfg_c, false);
      wait until reset_n_s = '1';
      for c in rx_cases_c'range
      loop
        if not rx_cases_c(c).bad_ndp then
          for i in 0 to rx_cases_c(c).count-1
          loop
            packet_get(frame_cfg_c, clock_s, rx_frame_s.m, rx_frame_s.s,
                       b, n, rej, state);
            check_bytes(name_c & " rx case " & to_string(c) & " frame " & to_string(i),
                        b(0 to n-1), pad_c & frame_of(rx_length(c, i), c * 64 + i));
            assert not rej
              report name_c & " rx: frame delivered rejected" severity failure;
            delivered := delivered + 1;
          end loop;
        end if;
      end loop;
      for i in 1 to 50 loop
        wait until rising_edge(clock_s);
      end loop;
      check_count(name_c & " rx ntb count", rx_stats_s.ntb_count, rx_cases_c'length);
      check_count(name_c & " rx datagram count", rx_stats_s.datagram_count, delivered);
      check_count(name_c & " rx header errors", rx_stats_s.header_error_count, 1);
      check_count(name_c & " rx NDP errors", rx_stats_s.ndp_error_count, 1);
      check_count(name_c & " rx datagram errors", rx_stats_s.datagram_error_count, 1);
      log_info(name_c & " receiver OK");
      done_s(index * 3) <= '1';
      wait;
    end process;

    receiver: nsl_usb.ncm.ncm_receiver
      generic map(
        ntb_config_c => ntb_cfg_c,
        frame_config_c => frame_cfg_c,
        ntb_max_size_c => ntb_max_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        ntb_i => rx_ntb_s.m,
        ntb_o => rx_ntb_s.s,
        frame_o => rx_frame_s.m,
        frame_i => rx_frame_s.s,
        stats_o => rx_stats_s
        );

    tx_stim: process is
      variable state : natural := index + 21;
    begin
      tx_frame_s.m <= transfer_defaults(frame_cfg_c);
      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);
      for i in 0 to tx_count_c-1
      loop
        if tx_rejected(i) then
          bytes_send(frame_cfg_c, clock_s, tx_frame_s.s, tx_frame_s.m,
                     pad_c & frame_of(tx_length(i), 200 + i), "1", state);
        else
          bytes_send(frame_cfg_c, clock_s, tx_frame_s.s, tx_frame_s.m,
                     pad_c & frame_of(tx_length(i), 200 + i), "0", state);
        end if;
      end loop;
      wait;
    end process;

    tx_check: process is
      variable b : buffer_t;
      variable n, state : natural := index + 31;
      variable rej : boolean;
      variable next_frame, blocks, block_len, ndp, ndp_len, idx, len : natural;
      variable seq, last_seq : integer := -1;
      variable good : natural := 0;
    begin
      tx_ntb_s.s <= accept(ntb_cfg_c, false);
      wait until reset_n_s = '1';
      next_frame := 0;
      blocks := 0;
      -- frames expected, in order
      while next_frame < tx_count_c
      loop
        if tx_length(next_frame) < 14 or tx_rejected(next_frame) then
          next_frame := next_frame + 1;
        else
          packet_get(ntb_cfg_c, clock_s, tx_ntb_s.m, tx_ntb_s.s, b, n, rej, state);
          blocks := blocks + 1;
          assert b(0 to 3) = ncm_nth16_signature_c
            report name_c & " tx: bad NTH16 signature" severity failure;
          assert get16(b, 4) = 12 report name_c & " tx: header length" severity failure;
          block_len := get16(b, 8);
          seq := get16(b, 6);
          assert block_len = n
            report name_c & " tx: wBlockLength " & to_string(block_len)
            & ", transfer " & to_string(n) severity failure;
          assert block_len mod 64 /= 0 and block_len mod 4 = 0
            report name_c & " tx: block length " & to_string(block_len) severity failure;
          assert last_seq = -1 or seq = (last_seq + 1) mod 65536
            report name_c & " tx: sequence" severity failure;
          last_seq := seq;
          ndp := get16(b, 10);
          assert b(ndp to ndp + 3) = ncm_ndp16_signature_c and get16(b, ndp + 6) = 0
            report name_c & " tx: bad NDP16" severity failure;
          ndp_len := get16(b, ndp + 4);
          for e in 0 to (ndp_len - 8) / 4 - 1
          loop
            idx := get16(b, ndp + 8 + 4 * e);
            len := get16(b, ndp + 10 + 4 * e);
            exit when idx = 0 and len = 0;
            assert idx mod 4 = 0 and idx >= 12 and idx + len <= ndp
              report name_c & " tx: entry " & to_string(idx) severity failure;
            while tx_length(next_frame) < 14 or tx_rejected(next_frame)
            loop
              next_frame := next_frame + 1;
            end loop;
            check_bytes(name_c & " tx frame " & to_string(next_frame),
                        b(idx to idx + len - 1),
                        frame_of(tx_length(next_frame), 200 + next_frame));
            next_frame := next_frame + 1;
            good := good + 1;
          end loop;
        end if;
      end loop;
      for i in 1 to 50 loop
        wait until rising_edge(clock_s);
      end loop;
      check_count(name_c & " tx datagram count", tx_stats_s.datagram_count, good);
      check_count(name_c & " tx drop count", tx_stats_s.drop_count, 2);
      check_count(name_c & " tx ntb count", tx_stats_s.ntb_count, blocks);
      log_info(name_c & " transmitter OK (" & to_string(good) & " frames in "
               & to_string(blocks) & " blocks)");
      done_s(index * 3 + 1) <= '1';
      wait;
    end process;

    transmitter: nsl_usb.ncm.ncm_transmitter
      generic map(
        frame_config_c => frame_cfg_c,
        ntb_config_c => ntb_cfg_c,
        ntb_max_size_c => ntb_max_c,
        zlp_avoid_size_c => 64
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        frame_i => tx_frame_s.m,
        frame_o => tx_frame_s.s,
        ntb_o => tx_ntb_s.m,
        ntb_i => tx_ntb_s.s,
        stats_o => tx_stats_s
        );

    loop_stim: process is
      variable state : natural := index + 41;
    begin
      loop_in_s.m <= transfer_defaults(frame_cfg_c);
      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);
      for i in 0 to 99
      loop
        bytes_send(frame_cfg_c, clock_s, loop_in_s.s, loop_in_s.m,
                   pad_c & frame_of(length_table_c(i mod 10), 500 + i), "0", state);
      end loop;
      wait;
    end process;

    loop_check: process is
      variable b : buffer_t;
      variable n, state : natural := index + 51;
      variable rej : boolean;
    begin
      loop_out_s.s <= accept(frame_cfg_c, false);
      wait until reset_n_s = '1';
      for i in 0 to 99
      loop
        packet_get(frame_cfg_c, clock_s, loop_out_s.m, loop_out_s.s, b, n, rej, state);
        check_bytes(name_c & " loopback frame " & to_string(i),
                    b(0 to n-1), pad_c & frame_of(length_table_c(i mod 10), 500 + i));
        assert not rej
          report name_c & " loopback: frame delivered rejected" severity failure;
      end loop;
      for i in 1 to 50 loop
        wait until rising_edge(clock_s);
      end loop;
      check_count(name_c & " loopback rx datagrams", loop_rx_stats_s.datagram_count, 100);
      check_count(name_c & " loopback rx errors",
                  loop_rx_stats_s.header_error_count + loop_rx_stats_s.ndp_error_count
                  + loop_rx_stats_s.datagram_error_count, 0);
      check_count(name_c & " loopback blocks", loop_rx_stats_s.ntb_count,
                  to_integer(loop_tx_stats_s.ntb_count));
      log_info(name_c & " loopback OK (" & to_string(to_integer(loop_tx_stats_s.ntb_count))
               & " blocks)");
      done_s(index * 3 + 2) <= '1';
      wait;
    end process;

    loop_transmitter: nsl_usb.ncm.ncm_transmitter
      generic map(
        frame_config_c => frame_cfg_c,
        ntb_config_c => ntb_cfg_c,
        ntb_max_size_c => ntb_max_c,
        zlp_avoid_size_c => 64
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        frame_i => loop_in_s.m,
        frame_o => loop_in_s.s,
        ntb_o => loop_mid_s.m,
        ntb_i => loop_mid_s.s,
        stats_o => loop_tx_stats_s
        );

    loop_receiver: nsl_usb.ncm.ncm_receiver
      generic map(
        ntb_config_c => ntb_cfg_c,
        frame_config_c => frame_cfg_c,
        ntb_max_size_c => ntb_max_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        ntb_i => loop_mid_s.m,
        ntb_o => loop_mid_s.s,
        frame_o => loop_out_s.m,
        frame_i => loop_out_s.s,
        stats_o => loop_rx_stats_s
        );

  end generate;

  bnoc: block is
    signal frame_in_s, frame_out_s : nsl_bnoc.committed.committed_bus;
    signal ntb_s : nsl_bnoc.framed.framed_bus;
    signal pipe_s : nsl_bnoc.pipe.pipe_bus_t;
    signal rx_stats_s : ncm_receiver_stats_t;
    signal tx_stats_s : ncm_transmitter_stats_t;
  begin

    stim: process is
      variable state : natural := 99;
      variable f : byte_string(0 to 1513);
      variable len : natural;
    begin
      frame_in_s.req <= nsl_bnoc.framed.framed_req_idle_c;
      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);
      for i in 0 to 29
      loop
        len := length_table_c(i mod 10);
        f(0 to len-1) := frame_of(len, 700 + i);
        for k in 0 to len
        loop
          frame_in_s.req.valid <= '1';
          if k < len then
            frame_in_s.req.data <= f(k);
            frame_in_s.req.last <= '0';
          elsif i = 13 then
            frame_in_s.req.data <= x"00";      -- invalid: dropped
            frame_in_s.req.last <= '1';
          else
            frame_in_s.req.data <= x"01";
            frame_in_s.req.last <= '1';
          end if;
          loop
            wait until rising_edge(clock_s);
            exit when frame_in_s.ack.ready = '1';
          end loop;
          frame_in_s.req <= nsl_bnoc.framed.framed_req_idle_c;
          stall(state, clock_s, 1);
        end loop;
      end loop;
      wait;
    end process;

    -- One NTB per framed frame; the receiver needs no boundaries.
    pipe_s.req.valid <= ntb_s.req.valid;
    pipe_s.req.data <= ntb_s.req.data;
    ntb_s.ack.ready <= pipe_s.ack.ready;

    check: process is
      variable state : natural := 199;
      variable got : byte_string(0 to 1513);
      variable n : natural;
      variable len : natural;
    begin
      frame_out_s.ack <= nsl_bnoc.framed.framed_ack_idle_c;
      wait until reset_n_s = '1';
      for i in 0 to 29
      loop
        if i /= 13 then
          len := length_table_c(i mod 10);
          n := 0;
          loop
            state := (state * 75 + 74) mod 65537;
            frame_out_s.ack.ready <= to_logic(state mod 3 /= 0);
            wait until rising_edge(clock_s);
            if frame_out_s.req.valid = '1' and frame_out_s.ack.ready = '1' then
              if frame_out_s.req.last = '1' then
                assert frame_out_s.req.data(0) = '1'
                  report "bnoc: frame not valid" severity failure;
                exit;
              end if;
              got(n) := frame_out_s.req.data;
              n := n + 1;
            end if;
          end loop;
          frame_out_s.ack.ready <= '0';
          check_bytes("bnoc loopback frame " & to_string(i),
                      got(0 to n-1), frame_of(len, 700 + i));
        end if;
      end loop;
      for i in 1 to 50 loop
        wait until rising_edge(clock_s);
      end loop;
      check_count("bnoc tx drops", tx_stats_s.drop_count, 0);
      check_count("bnoc rx datagrams", rx_stats_s.datagram_count, 29);
      log_info("bnoc loopback OK");
      done_s(config_count_c * 3) <= '1';
      wait;
    end process;

    tx: nsl_usb.ncm.ncm_transmitter_bnoc
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        frame_i => frame_in_s.req,
        frame_o => frame_in_s.ack,
        ntb_o => ntb_s.req,
        ntb_i => ntb_s.ack,
        stats_o => tx_stats_s
        );

    rx: nsl_usb.ncm.ncm_receiver_bnoc
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        ntb_i => pipe_s.req,
        ntb_o => pipe_s.ack,
        frame_o => frame_out_s.req,
        frame_i => frame_out_s.ack,
        stats_o => rx_stats_s
        );

  end block;

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
