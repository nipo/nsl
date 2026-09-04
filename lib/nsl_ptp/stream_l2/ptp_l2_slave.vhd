library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_inet, nsl_logic, nsl_math, nsl_mii, nsl_time, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;
use work.ptp.all;

entity ptp_l2_slave is
  generic(
    config_c : config_t;
    header_length_c : integer_vector;
    clock_i_hz_c : natural;
    domain_c : natural := 0;
    delay_req_period_c : natural := 1;
    sync_timeout_c : natural := 8;
    step_threshold_ns_c : natural := 100000000;
    multicast_group_c : natural := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    clock_identity_i : in byte_string(0 to 7);

    timestamp_i : in timestamp_t;

    capture_id_o : out tag_id_t;
    capture_time_i : in timestamp_t;

    tx_strobe_i : in std_ulogic;
    tx_id_i : in tag_id_t;

    rx_i : in master_t;
    rx_o : out slave_t;
    tx_o : out master_t;
    tx_i : in slave_t;

    offset_o : out timestamp_nanosecond_offset_t;
    offset_valid_o : out std_ulogic;
    step_o : out timestamp_t;
    step_valid_o : out std_ulogic;
    path_delay_o : out timestamp_nanosecond_offset_t;
    locked_o : out std_ulogic
    );
end entity;

architecture beh of ptp_l2_slave is

  constant ns_per_second_c : natural := 1000000000;
  -- Beyond this, a messageLength field is taken as garbage.
  constant message_length_max_c : natural := 1500;

  -- Transported size of the tag and layer-2 context blocks, which the
  -- receive side steps over and the transmit side crafts.
  constant hdr_size_c : natural := context_byte_count(config_c, header_length_c);
  constant rx_msg_pos_c : natural := hdr_size_c;
  constant rx_max_pos_c : natural := hdr_size_c + ptp_delay_resp_length_c;
  constant tx_length_c : natural := hdr_size_c + ptp_delay_req_length_c;

  constant l2_ctx_c : byte_string(0 to l2_context_length_c-1)
    := to_bytes(l2_context_t'(peer => ptp_multicast_addr_c,
                             casting => l2_multicast(multicast_group_c)));

  -- Only one event frame is outstanding at a time, so any fixed
  -- identifier designates it unambiguously.
  constant tx_tag_id_c : tag_id_t := "0000";

  -- Nanosecond arithmetic domain, wide enough for the sum of two
  -- in-range differences plus a wire correction.
  subtype ns_t is signed(33 downto 0);
  -- Normalization domain, wide enough for a nanosecond field plus a
  -- full-range correction.
  subtype acc_t is signed(35 downto 0);

  constant ns_c : acc_t := to_signed(ns_per_second_c, acc_t'length);

  -- Seconds an unanswered Delay_Req blocks the next one.
  constant dreq_abandon_c : natural := 4;
  constant ns_zero_c : ns_t := (others => '0');

  type message_t is
  record
    type_byte: byte;
    version_byte: byte;
    domain_byte: byte;
    len: byte_string(0 to 1);
    flags0: byte;
    seq: byte_string(0 to 1);
    source_id: ptp_port_identity_t;
    req_id: ptp_port_identity_t;
    -- Nanosecond part of correctionField, i.e. bits 47 downto 16.
    corr: byte_string(0 to 3);
    ts: ptp_timestamp_bytes_t;
    capture: timestamp_t;
    -- Whether the packet carried a whole fixed-size message of the
    -- corresponding class.
    got_short: boolean;
    got_long: boolean;
  end record;

  constant message_none_c : message_t := (
    type_byte => (others => '0'),
    version_byte => (others => '0'),
    domain_byte => (others => '0'),
    len => (others => (others => '0')),
    flags0 => (others => '0'),
    seq => (others => (others => '0')),
    source_id => (others => (others => '0')),
    req_id => (others => (others => '0')),
    corr => (others => (others => '0')),
    ts => (others => (others => '0')),
    capture => timestamp_zero_c,
    got_short => false,
    got_long => false
    );

  function msg_type(m: message_t) return natural
  is
  begin
    return to_integer(unsigned(m.type_byte(3 downto 0)));
  end function;

  function msg_seq(m: message_t) return unsigned
  is
  begin
    return from_be(m.seq);
  end function;

  function msg_corr(m: message_t) return signed
  is
  begin
    return signed(from_be(m.corr));
  end function;

  function msg_two_step(m: message_t) return boolean
  is
  begin
    return m.flags0(ptp_flag0_two_step_c) = '1';
  end function;

  -- Header sanity and message class filtering.
  function acceptable(m: message_t) return boolean
  is
    variable mt_v: natural;
    variable len_v: natural;
  begin
    if not m.got_short then
      return false;
    end if;

    if to_integer(unsigned(m.type_byte(7 downto 4))) /= 0 then
      return false;
    end if;

    if to_integer(unsigned(m.version_byte(3 downto 0))) /= 2 then
      return false;
    end if;

    if to_integer(unsigned(m.domain_byte)) /= domain_c then
      return false;
    end if;

    mt_v := msg_type(m);
    len_v := to_integer(from_be(m.len));

    if len_v > message_length_max_c then
      return false;
    end if;

    if mt_v = ptp_msg_sync_c or mt_v = ptp_msg_follow_up_c then
      return len_v >= ptp_sync_length_c;
    elsif mt_v = ptp_msg_delay_resp_c then
      return m.got_long and len_v >= ptp_delay_resp_length_c;
    end if;

    return false;
  end function;

  function own_identity(id: byte_string) return ptp_port_identity_t
  is
    alias xi: byte_string(0 to 7) is id;
    variable ret: ptp_port_identity_t;
  begin
    ret(0 to 7) := xi;
    ret(8) := to_byte(0);
    ret(9) := to_byte(1);
    return ret;
  end function;

  type tx_request_t is
  record
    seq: byte_string(0 to 1);
    source_id: ptp_port_identity_t;
  end record;

  function message_byte(req: tx_request_t; pos: natural) return byte
  is
    constant len_c : byte_string(0 to 1)
      := to_be(to_unsigned(ptp_delay_req_length_c, 16));
  begin
    if pos = ptp_off_type_c then
      return to_byte(ptp_msg_delay_req_c);
    elsif pos = ptp_off_version_c then
      return to_byte(2);
    elsif pos >= ptp_off_length_c and pos < ptp_off_length_c + 2 then
      return len_c(pos - ptp_off_length_c);
    elsif pos = ptp_off_domain_c then
      return to_byte(domain_c);
    elsif pos >= ptp_off_source_port_identity_c
      and pos < ptp_off_source_port_identity_c + ptp_port_identity_t'length then
      return req.source_id(pos - ptp_off_source_port_identity_c);
    elsif pos >= ptp_off_sequence_id_c and pos < ptp_off_sequence_id_c + 2 then
      return req.seq(pos - ptp_off_sequence_id_c);
    elsif pos = ptp_off_control_c then
      return to_byte(1);
    elsif pos = ptp_off_log_interval_c then
      return to_byte(16#7f#);
    end if;

    return to_byte(0);
  end function;

  function tx_byte(req: tx_request_t; pos: natural) return byte_string
  is
    variable ret: byte_string(0 to config_c.data_width-1);
  begin
    if pos < tag_length_c then
      ret(0) := tag_build(true, tx_tag_id_c);
    elsif pos < tag_length_c + l2_context_length_c then
      ret(0) := l2_ctx_c(pos - tag_length_c);
    elsif pos < hdr_size_c then
      ret(0) := to_byte(0);
    else
      ret(0) := message_byte(req, pos - hdr_size_c);
    end if;

    return ret;
  end function;

  signal tick_s : std_ulogic;

  signal send_req_s, send_done_s : std_ulogic;
  signal tx_req_s : tx_request_t;

  signal msg_valid_s, msg_ack_s : std_ulogic;
  signal msg_s : message_t;

begin

  assert config_c.data_width = 1
    report "PTP slave only supports a byte-wide stream"
    severity failure;

  assert header_length_c'length = 2
    report "PTP slave expects the tag and layer-2 context blocks only"
    severity failure;

  assert header_length_c(header_length_c'low) = tag_length_c
    report "PTP slave expects the timestamping tag as first block"
    severity failure;

  assert header_length_c(header_length_c'high) = l2_context_length_c
    report "PTP slave expects the layer-2 context as second block"
    severity failure;

  assert step_threshold_ns_c < 2 ** 30
    report "PTP slave step threshold must fit in the offset range"
    severity failure;

  assert delay_req_period_c >= 1
    report "PTP slave delay request period must be at least one second"
    severity failure;

  assert sync_timeout_c >= 1
    report "PTP slave sync timeout must be at least one second"
    severity failure;

  ticker: block is
    constant tick_div_c : natural := clock_i_hz_c;

    type regs_t is
    record
      left: integer range 0 to tick_div_c-1;
      tick: std_ulogic;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.left <= tick_div_c - 1;
        r.tick <= '0';
      end if;
    end process;

    transition: process(r) is
    begin
      rin <= r;

      rin.tick <= '0';
      if r.left /= 0 then
        rin.left <= r.left - 1;
      else
        rin.left <= tick_div_c - 1;
        rin.tick <= '1';
      end if;
    end process;

    moore: process(r) is
    begin
      tick_s <= r.tick;
    end process;
  end block;

  sender: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_SEND,
      ST_DONE
      );

    type regs_t is
    record
      state: state_t;
      req: tx_request_t;
      pos: integer range 0 to tx_length_c-1;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, tx_i, send_req_s, tx_req_s) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.pos <= 0;

        when ST_IDLE =>
          if send_req_s = '1' then
            rin.state <= ST_SEND;
            rin.req <= tx_req_s;
            rin.pos <= 0;
          end if;

        when ST_SEND =>
          if is_ready(config_c, tx_i) then
            if r.pos = tx_length_c-1 then
              rin.state <= ST_DONE;
            else
              rin.pos <= r.pos + 1;
            end if;
          end if;

        when ST_DONE =>
          rin.state <= ST_IDLE;
      end case;
    end process;

    moore: process(r) is
    begin
      tx_o <= transfer(config_c,
                       bytes => tx_byte(r.req, r.pos),
                       user => "0",
                       valid => r.state = ST_SEND,
                       last => r.pos = tx_length_c-1);
      send_done_s <= to_logic(r.state = ST_DONE);
    end process;
  end block;

  receiver: block is
    type state_t is (
      ST_MESSAGE,
      ST_DRAIN
      );

    type regs_t is
    record
      state: state_t;
      pos: integer range 0 to rx_max_pos_c;
      tag: byte;
      rejected: boolean;
      last_seen: boolean;
      acc: message_t;
      held: message_t;
      msg_valid: boolean;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_MESSAGE;
        r.pos <= 0;
        r.tag <= (others => '0');
        r.rejected <= false;
        r.last_seen <= false;
        r.acc <= message_none_c;
        r.held <= message_none_c;
        r.msg_valid <= false;
      end if;
    end process;

    transition: process(r, rx_i, capture_time_i, msg_ack_s) is
      variable rx_data: byte;
      variable mp: integer;
    begin
      rin <= r;
      rx_data := bytes(config_c, rx_i)(0);
      mp := r.pos - rx_msg_pos_c;

      if msg_ack_s = '1' then
        rin.msg_valid <= false;
      end if;

      if r.last_seen then
        -- Decision cycle: the parse state has settled and the input is
        -- held off for this single beat.
        rin.last_seen <= false;
        rin.state <= ST_MESSAGE;
        rin.pos <= 0;
        rin.rejected <= false;
        rin.acc <= message_none_c;

        if not r.rejected and not r.msg_valid and acceptable(r.acc) then
          rin.msg_valid <= true;
          rin.held <= r.acc;
        end if;
      elsif is_valid(config_c, rx_i) then
        case r.state is
          when ST_MESSAGE =>
            if r.pos = 0 then
              -- The tag byte designates the capture register holding
              -- this frame's SFD time, read in the same cycle.
              rin.tag <= rx_data;
              rin.acc.capture <= capture_time_i;
            end if;

            if r.pos >= rx_msg_pos_c then
              if mp = ptp_off_type_c then
                rin.acc.type_byte <= rx_data;
              end if;

              if mp = ptp_off_version_c then
                rin.acc.version_byte <= rx_data;
              end if;

              if mp >= ptp_off_length_c and mp < ptp_off_length_c + 2 then
                rin.acc.len(mp - ptp_off_length_c) <= rx_data;
              end if;

              if mp = ptp_off_domain_c then
                rin.acc.domain_byte <= rx_data;
              end if;

              if mp = ptp_off_flags_c then
                rin.acc.flags0 <= rx_data;
              end if;

              if mp >= ptp_off_correction_c + 2
                and mp < ptp_off_correction_c + 6 then
                rin.acc.corr(mp - ptp_off_correction_c - 2) <= rx_data;
              end if;

              if mp >= ptp_off_source_port_identity_c
                and mp < ptp_off_source_port_identity_c + 10 then
                rin.acc.source_id(mp - ptp_off_source_port_identity_c)
                  <= rx_data;
              end if;

              if mp >= ptp_off_sequence_id_c
                and mp < ptp_off_sequence_id_c + 2 then
                rin.acc.seq(mp - ptp_off_sequence_id_c) <= rx_data;
              end if;

              if mp >= ptp_off_timestamp_c
                and mp < ptp_off_timestamp_c + 10 then
                rin.acc.ts(mp - ptp_off_timestamp_c) <= rx_data;
              end if;

              if mp >= ptp_off_requesting_port_identity_c
                and mp < ptp_off_requesting_port_identity_c + 10 then
                rin.acc.req_id(mp - ptp_off_requesting_port_identity_c)
                  <= rx_data;
              end if;

              if mp = ptp_sync_length_c - 1 then
                rin.acc.got_short <= true;
              end if;

              if mp = ptp_delay_resp_length_c - 1 then
                rin.acc.got_long <= true;
              end if;
            end if;

            if r.pos = rx_max_pos_c-1 then
              rin.state <= ST_DRAIN;
              rin.pos <= rx_max_pos_c;
            else
              rin.pos <= r.pos + 1;
            end if;

          when ST_DRAIN =>
            null;
        end case;

        if is_last(config_c, rx_i) then
          rin.last_seen <= true;
          rin.rejected <= is_rejected(config_c, rx_i);
        end if;
      end if;
    end process;

    moore: process(r) is
    begin
      rx_o <= accept(config_c, not r.last_seen);
      msg_valid_s <= to_logic(r.msg_valid);
      msg_s <= r.held;
    end process;

    mealy: process(r, rx_i) is
    begin
      if r.pos = 0 then
        capture_id_o <= tag_id(bytes(config_c, rx_i)(0));
      else
        capture_id_o <= tag_id(r.tag);
      end if;
    end process;
  end block;

  client: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      -- Shared arithmetic sequences, returning to r.ret
      ST_DIFF0,
      ST_DIFF1,
      ST_DIFF2,
      ST_ADD0,
      ST_ADD1,
      -- Master time collection and offset production
      ST_T1_READY,
      ST_A_READY,
      ST_DECIDE,
      ST_STEP,
      ST_STEP_LAG,
      ST_STEP_READY,
      -- Delay request exchange
      ST_D_READY,
      ST_MPD,
      ST_PDELAY,
      ST_SEND
      );

    type regs_t is
    record
      state: state_t;
      ret: state_t;

      locked: boolean;
      master_id: ptp_port_identity_t;
      sync_seq: unsigned(15 downto 0);
      await_fu: boolean;
      corr: signed(31 downto 0);
      t1: timestamp_t;
      t2: timestamp_t;

      dreq_seq: unsigned(15 downto 0);
      dreq_sent: unsigned(15 downto 0);
      dreq_pending: boolean;
      -- A request is outstanding: the next one waits for its answer,
      -- or for the abandon timeout.
      dreq_open: boolean;
      dreq_age: integer range 0 to dreq_abandon_c;
      t3_wait: boolean;
      t3_valid: boolean;
      t3: timestamp_t;
      dresp_corr: signed(31 downto 0);

      a_last: ns_t;
      a_valid: boolean;
      b: ns_t;
      mpd: ns_t;
      mpd_valid: boolean;
      pdelay: ns_t;

      offset: ns_t;
      offset_valid: boolean;
      step: timestamp_t;
      step_valid: boolean;

      sync_timer: integer range 0 to sync_timeout_c;
      dreq_timer: integer range 0 to delay_req_period_c;

      msg_ack: boolean;
      own_id: ptp_port_identity_t;

      ts_a: timestamp_t;
      ts_b: timestamp_t;
      ts_r: timestamp_t;
      delta: signed(31 downto 0);
      ds: acc_t;
      dn: acc_t;
      res: ns_t;
      res_ok: boolean;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
        r.locked <= false;
        r.await_fu <= false;
        r.dreq_pending <= false;
        r.dreq_open <= false;
        r.t3_wait <= false;
        r.t3_valid <= false;
        r.a_valid <= false;
        r.mpd_valid <= false;
        r.offset_valid <= false;
        r.step_valid <= false;
        r.msg_ack <= false;
        r.dreq_seq <= (others => '0');
        r.pdelay <= ns_zero_c;
        r.offset <= ns_zero_c;
      end if;
    end process;

    transition: process(r, enable_i, clock_identity_i, timestamp_i,
                        tx_strobe_i, tick_s, send_done_s,
                        msg_valid_s, msg_s) is
      variable mpd_v: ns_t;
      variable mt_v: natural;
    begin
      rin <= r;

      rin.offset_valid <= false;
      rin.step_valid <= false;
      rin.msg_ack <= false;
      rin.own_id <= own_identity(clock_identity_i);

      if r.mpd_valid then
        mpd_v := r.mpd;
      else
        -- Before any delay exchange completes, the one-way delay is
        -- unknown and taken as zero.
        mpd_v := ns_zero_c;
      end if;

      mt_v := msg_type(msg_s);

      -- The transmit strobe of the only outstanding event frame gives
      -- T3, whatever the state the rest of the engine is in.
      if tx_strobe_i = '1' and r.t3_wait then
        rin.t3_wait <= false;
        rin.t3_valid <= true;
        rin.t3 <= timestamp_i;
      end if;

      if tick_s = '1' and r.locked then
        if r.sync_timer /= 0 then
          rin.sync_timer <= r.sync_timer - 1;

          if r.dreq_timer /= 0 then
            rin.dreq_timer <= r.dreq_timer - 1;
          else
            rin.dreq_timer <= delay_req_period_c - 1;
            rin.dreq_pending <= true;
          end if;

          if r.dreq_open then
            if r.dreq_age /= dreq_abandon_c then
              rin.dreq_age <= r.dreq_age + 1;
            else
              rin.dreq_open <= false;
            end if;
          end if;
        else
          rin.locked <= false;
          rin.await_fu <= false;
          rin.dreq_pending <= false;
          rin.dreq_open <= false;
          rin.t3_valid <= false;
          rin.a_valid <= false;
          rin.mpd_valid <= false;
          rin.pdelay <= ns_zero_c;
        end if;
      end if;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if msg_valid_s = '1' and not r.msg_ack then
            rin.msg_ack <= true;

            if mt_v = ptp_msg_sync_c then
              if not r.locked or r.master_id = msg_s.source_id then
                rin.locked <= true;
                rin.master_id <= msg_s.source_id;
                rin.sync_timer <= sync_timeout_c;
                rin.t2 <= msg_s.capture;
                rin.sync_seq <= msg_seq(msg_s);
                rin.corr <= msg_corr(msg_s);

                if not r.locked then
                  rin.dreq_timer <= delay_req_period_c - 1;
                end if;

                if msg_two_step(msg_s) then
                  rin.await_fu <= true;
                else
                  rin.await_fu <= false;
                  rin.ts_a <= from_ptp_timestamp(msg_s.ts);
                  rin.delta <= msg_corr(msg_s);
                  rin.state <= ST_ADD0;
                  rin.ret <= ST_T1_READY;
                end if;
              end if;

            elsif mt_v = ptp_msg_follow_up_c then
              if r.locked and r.await_fu
                and r.master_id = msg_s.source_id
                and r.sync_seq = msg_seq(msg_s) then
                rin.await_fu <= false;
                rin.ts_a <= from_ptp_timestamp(msg_s.ts);
                rin.delta <= r.corr + msg_corr(msg_s);
                rin.state <= ST_ADD0;
                rin.ret <= ST_T1_READY;
              end if;

            elsif mt_v = ptp_msg_delay_resp_c then
              if r.locked and r.t3_valid
                and r.master_id = msg_s.source_id
                and r.dreq_sent = msg_seq(msg_s)
                and own_identity(clock_identity_i) = msg_s.req_id then
                rin.t3_valid <= false;
                rin.dreq_open <= false;
                rin.dresp_corr <= msg_corr(msg_s);
                rin.ts_a <= from_ptp_timestamp(msg_s.ts);
                rin.ts_b <= r.t3;
                rin.state <= ST_DIFF0;
                rin.ret <= ST_D_READY;
              end if;
            end if;

          elsif r.dreq_pending and r.locked and not r.dreq_open then
            rin.dreq_pending <= false;
            rin.dreq_open <= true;
            rin.dreq_age <= 0;
            rin.dreq_sent <= r.dreq_seq;
            rin.t3_wait <= true;
            rin.t3_valid <= false;
            rin.state <= ST_SEND;
          end if;

        when ST_DIFF0 =>
          rin.ds <= signed(resize(r.ts_a.second, acc_t'length))
                    - signed(resize(r.ts_b.second, acc_t'length));
          rin.dn <= signed(resize(r.ts_a.nanosecond, acc_t'length))
                    - signed(resize(r.ts_b.nanosecond, acc_t'length));
          rin.state <= ST_DIFF1;

        when ST_DIFF1 =>
          if r.dn < 0 then
            rin.dn <= r.dn + ns_c;
            rin.ds <= r.ds - 1;
          end if;
          rin.state <= ST_DIFF2;

        when ST_DIFF2 =>
          -- A normalized difference only fits the nanosecond offset
          -- range when the second parts differ by zero or one.
          if r.ds = 0 then
            rin.res <= resize(r.dn, ns_t'length);
            rin.res_ok <= true;
          elsif r.ds = -1 then
            rin.res <= resize(r.dn - ns_c, ns_t'length);
            rin.res_ok <= true;
          else
            rin.res <= ns_zero_c;
            rin.res_ok <= false;
          end if;
          rin.state <= r.ret;

        when ST_ADD0 =>
          rin.dn <= signed(resize(r.ts_a.nanosecond, acc_t'length))
                    + resize(r.delta, acc_t'length);
          rin.ds <= signed(resize(r.ts_a.second, acc_t'length));
          rin.state <= ST_ADD1;

        when ST_ADD1 =>
          if r.dn < 0 then
            rin.dn <= r.dn + ns_c;
            rin.ds <= r.ds - 1;
          elsif r.dn >= ns_c then
            rin.dn <= r.dn - ns_c;
            rin.ds <= r.ds + 1;
          else
            rin.ts_r.abs_change <= '0';
            rin.ts_r.second <= unsigned(r.ds(31 downto 0));
            rin.ts_r.nanosecond <= unsigned(r.dn(29 downto 0));
            rin.state <= r.ret;
          end if;

        when ST_T1_READY =>
          rin.t1 <= r.ts_r;
          rin.ts_a <= r.t2;
          rin.ts_b <= r.ts_r;
          rin.state <= ST_DIFF0;
          rin.ret <= ST_A_READY;

        when ST_A_READY =>
          if r.res_ok then
            rin.a_last <= r.res;
            rin.a_valid <= true;
            rin.offset <= r.res - mpd_v;
            rin.state <= ST_DECIDE;
          else
            rin.a_valid <= false;
            rin.state <= ST_STEP;
          end if;

        when ST_DECIDE =>
          if r.offset > to_signed(step_threshold_ns_c, ns_t'length)
            or r.offset < -to_signed(step_threshold_ns_c, ns_t'length) then
            rin.state <= ST_STEP;
          else
            rin.offset_valid <= true;
            rin.state <= ST_IDLE;
          end if;

        when ST_STEP =>
          -- The step must land as master time at application, not at
          -- the Sync's departure: the local time elapsed since the
          -- Sync arrived is measured and added on top of T1 and the
          -- path delay, compensating the frames and the processing
          -- in between.
          rin.ts_a <= timestamp_i;
          rin.ts_b <= r.t2;
          rin.state <= ST_DIFF0;
          rin.ret <= ST_STEP_LAG;

        when ST_STEP_LAG =>
          rin.ts_a <= r.t1;
          if r.res_ok then
            rin.delta <= resize(mpd_v + r.res, 32);
          else
            rin.delta <= resize(mpd_v, 32);
          end if;
          rin.state <= ST_ADD0;
          rin.ret <= ST_STEP_READY;

        when ST_STEP_READY =>
          rin.step <= r.ts_r;
          rin.step.abs_change <= '1';
          rin.step_valid <= true;
          rin.state <= ST_IDLE;

        when ST_D_READY =>
          if r.res_ok then
            -- The residence time the master reports in the Delay_Resp
            -- correctionField is time the request spent in transit
            -- bridges, and leaves the slave-to-master term.
            rin.b <= r.res - resize(r.dresp_corr, ns_t'length);
            rin.state <= ST_MPD;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_MPD =>
          if r.a_valid then
            rin.mpd <= shift_right(r.a_last + r.b, 1);
            rin.mpd_valid <= true;
            rin.state <= ST_PDELAY;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_PDELAY =>
          -- A negative mean path delay is measurement noise; it is
          -- reported as zero but kept as measured for the offset.
          if r.mpd < 0 then
            rin.pdelay <= ns_zero_c;
          else
            rin.pdelay <= r.mpd;
          end if;
          rin.state <= ST_IDLE;

        when ST_SEND =>
          if send_done_s = '1' then
            rin.dreq_seq <= r.dreq_seq + 1;
            rin.state <= ST_IDLE;
          end if;
      end case;

      if enable_i = '0' then
        rin.locked <= false;
        rin.await_fu <= false;
        rin.dreq_pending <= false;
        rin.t3_valid <= false;
        rin.a_valid <= false;
        rin.mpd_valid <= false;
        rin.pdelay <= ns_zero_c;
        rin.offset_valid <= false;
        rin.step_valid <= false;

        -- A request being emitted is carried to its last beat: the
        -- stream contract forbids truncating a packet.
        if r.state /= ST_SEND then
          rin.state <= ST_IDLE;
        end if;
      end if;
    end process;

    moore: process(r) is
    begin
      send_req_s <= to_logic(r.state = ST_SEND);
      msg_ack_s <= to_logic(r.msg_ack);
      tx_req_s.seq <= to_be(r.dreq_seq);
      tx_req_s.source_id <= r.own_id;

      offset_o <= resize(r.offset, timestamp_nanosecond_offset_t'length);
      offset_valid_o <= to_logic(r.offset_valid);
      step_o <= r.step;
      step_valid_o <= to_logic(r.step_valid);
      path_delay_o <= resize(r.pdelay, timestamp_nanosecond_offset_t'length);
      locked_o <= to_logic(r.locked);
    end process;
  end block;

end architecture;
