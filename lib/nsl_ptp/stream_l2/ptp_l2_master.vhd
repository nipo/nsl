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

entity ptp_l2_master is
  generic(
    config_c : config_t;
    header_length_c : integer_vector;
    clock_i_hz_c : natural;
    domain_c : natural := 0;
    sync_period_c : natural := 1;
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
    tx_i : in slave_t
    );
end entity;

-- Every emitted message carries a zero correctionField: the engine is
-- an end station, it inserts no residence time, and the transmit
-- timestamp of an event message travels in the Follow_Up rather than
-- in a correction.  The residence time a Delay_Req accumulated in
-- transit bridges is therefore not echoed in the Delay_Resp; a slave
-- behind transparent clocks sees that part of the path as symmetric
-- delay.
architecture beh of ptp_l2_master is

  -- Beyond this, a messageLength field is taken as garbage.
  constant message_length_max_c : natural := 1500;

  -- Transported size of the tag and layer-2 context blocks, which the
  -- receive side steps over and the transmit side crafts.
  constant hdr_size_c : natural := context_byte_count(config_c, header_length_c);
  constant rx_msg_pos_c : natural := hdr_size_c;
  constant rx_max_pos_c : natural := hdr_size_c + ptp_delay_req_length_c;
  constant tx_short_c : natural := hdr_size_c + ptp_sync_length_c;
  constant tx_long_c : natural := hdr_size_c + ptp_delay_resp_length_c;

  constant l2_ctx_c : byte_string(0 to l2_context_length_c-1)
    := to_bytes(l2_context_t'(peer => ptp_multicast_addr_c,
                             casting => l2_multicast(multicast_group_c)));

  -- Only one event frame is outstanding at a time, so any fixed
  -- identifier designates it unambiguously.
  constant tx_tag_id_c : tag_id_t := "0000";

  type message_t is
  record
    type_byte: byte;
    version_byte: byte;
    domain_byte: byte;
    len: byte_string(0 to 1);
    seq: byte_string(0 to 1);
    source_id: ptp_port_identity_t;
    capture: timestamp_t;
    -- Whether the packet carried a whole fixed-size message.
    got_short: boolean;
  end record;

  constant message_none_c : message_t := (
    type_byte => (others => '0'),
    version_byte => (others => '0'),
    domain_byte => (others => '0'),
    len => (others => (others => '0')),
    seq => (others => (others => '0')),
    source_id => (others => (others => '0')),
    capture => timestamp_zero_c,
    got_short => false
    );

  function msg_type(m: message_t) return natural
  is
  begin
    return to_integer(unsigned(m.type_byte(3 downto 0)));
  end function;

  -- Header sanity and message class filtering.
  function acceptable(m: message_t) return boolean
  is
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

    if msg_type(m) /= ptp_msg_delay_req_c then
      return false;
    end if;

    len_v := to_integer(from_be(m.len));

    return len_v >= ptp_delay_req_length_c and len_v <= message_length_max_c;
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
    msg_type: byte;
    seq: byte_string(0 to 1);
    ts: timestamp_t;
    req_id: ptp_port_identity_t;
    source_id: ptp_port_identity_t;
    strobe: boolean;
  end record;

  function tx_length(req: tx_request_t) return natural
  is
  begin
    if to_integer(unsigned(req.msg_type(3 downto 0))) = ptp_msg_delay_resp_c then
      return tx_long_c;
    end if;

    return tx_short_c;
  end function;

  function message_byte(req: tx_request_t; pos: natural) return byte
  is
    variable mt_v: natural;
    variable len_v: byte_string(0 to 1);
    variable ts_v: ptp_timestamp_bytes_t;
  begin
    mt_v := to_integer(unsigned(req.msg_type(3 downto 0)));
    len_v := to_be(to_unsigned(tx_length(req) - hdr_size_c, 16));
    ts_v := to_ptp_timestamp(req.ts);

    if pos = ptp_off_type_c then
      return req.msg_type;
    elsif pos = ptp_off_version_c then
      return to_byte(2);
    elsif pos >= ptp_off_length_c and pos < ptp_off_length_c + 2 then
      return len_v(pos - ptp_off_length_c);
    elsif pos = ptp_off_domain_c then
      return to_byte(domain_c);
    elsif pos = ptp_off_flags_c then
      if mt_v = ptp_msg_sync_c then
        return to_byte(2 ** ptp_flag0_two_step_c);
      end if;
      return to_byte(0);
    elsif pos >= ptp_off_source_port_identity_c
      and pos < ptp_off_source_port_identity_c + ptp_port_identity_t'length then
      return req.source_id(pos - ptp_off_source_port_identity_c);
    elsif pos >= ptp_off_sequence_id_c and pos < ptp_off_sequence_id_c + 2 then
      return req.seq(pos - ptp_off_sequence_id_c);
    elsif pos = ptp_off_control_c then
      if mt_v = ptp_msg_sync_c then
        return to_byte(0);
      elsif mt_v = ptp_msg_follow_up_c then
        return to_byte(2);
      end if;
      return to_byte(3);
    elsif pos = ptp_off_log_interval_c then
      if mt_v = ptp_msg_delay_resp_c then
        return to_byte(16#7f#);
      end if;
      return to_byte(0);
    elsif pos >= ptp_off_timestamp_c
      and pos < ptp_off_timestamp_c + ptp_timestamp_bytes_t'length then
      return ts_v(pos - ptp_off_timestamp_c);
    elsif pos >= ptp_off_requesting_port_identity_c
      and pos < ptp_off_requesting_port_identity_c
      + ptp_port_identity_t'length then
      return req.req_id(pos - ptp_off_requesting_port_identity_c);
    end if;

    return to_byte(0);
  end function;

  function tx_byte(req: tx_request_t; pos: natural) return byte_string
  is
    variable ret: byte_string(0 to config_c.data_width-1);
  begin
    if pos < tag_length_c then
      ret(0) := tag_build(req.strobe, tx_tag_id_c);
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
    report "PTP master only supports a byte-wide stream"
    severity failure;

  assert header_length_c'length = 2
    report "PTP master expects the tag and layer-2 context blocks only"
    severity failure;

  assert header_length_c(header_length_c'low) = tag_length_c
    report "PTP master expects the timestamping tag as first block"
    severity failure;

  assert header_length_c(header_length_c'high) = l2_context_length_c
    report "PTP master expects the layer-2 context as second block"
    severity failure;

  assert sync_period_c >= 1
    report "PTP master sync period must be at least one second"
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
      len: integer range 1 to tx_long_c;
      pos: integer range 0 to tx_long_c-1;
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
          rin.len <= tx_short_c;

        when ST_IDLE =>
          if send_req_s = '1' then
            rin.state <= ST_SEND;
            rin.req <= tx_req_s;
            rin.len <= tx_length(tx_req_s);
            rin.pos <= 0;
          end if;

        when ST_SEND =>
          if is_ready(config_c, tx_i) then
            if r.pos = r.len-1 then
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
                       last => r.pos = r.len-1);
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

              if mp >= ptp_off_source_port_identity_c
                and mp < ptp_off_source_port_identity_c + 10 then
                rin.acc.source_id(mp - ptp_off_source_port_identity_c)
                  <= rx_data;
              end if;

              if mp >= ptp_off_sequence_id_c
                and mp < ptp_off_sequence_id_c + 2 then
                rin.acc.seq(mp - ptp_off_sequence_id_c) <= rx_data;
              end if;

              if mp = ptp_delay_req_length_c - 1 then
                rin.acc.got_short <= true;
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
      ST_SYNC,
      ST_SYNC_WAIT,
      ST_FOLLOW_UP,
      ST_RESP
      );

    type regs_t is
    record
      state: state_t;

      seq: unsigned(15 downto 0);
      sync_pending: boolean;
      sync_timer: integer range 0 to sync_period_c;

      t1: timestamp_t;
      t1_wait: boolean;
      t1_valid: boolean;

      resp_pending: boolean;
      resp_seq: byte_string(0 to 1);
      resp_id: ptp_port_identity_t;
      t4: timestamp_t;

      own_id: ptp_port_identity_t;
      msg_ack: boolean;
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
        r.seq <= (others => '0');
        r.sync_pending <= false;
        r.sync_timer <= sync_period_c - 1;
        r.t1_wait <= false;
        r.t1_valid <= false;
        r.resp_pending <= false;
        r.msg_ack <= false;
      end if;
    end process;

    transition: process(r, enable_i, clock_identity_i, timestamp_i,
                        tx_strobe_i, tick_s, send_done_s,
                        msg_valid_s, msg_s) is
      variable mt_v: natural;
    begin
      rin <= r;

      rin.msg_ack <= false;
      rin.own_id <= own_identity(clock_identity_i);
      mt_v := msg_type(msg_s);

      -- The transmit strobe of the only outstanding event frame gives
      -- T1, whatever the state the rest of the engine is in.
      if tx_strobe_i = '1' and r.t1_wait then
        rin.t1_wait <= false;
        rin.t1_valid <= true;
        rin.t1 <= timestamp_i;
      end if;

      if tick_s = '1' then
        if r.sync_timer /= 0 then
          rin.sync_timer <= r.sync_timer - 1;
        else
          rin.sync_timer <= sync_period_c - 1;
          rin.sync_pending <= true;
        end if;
      end if;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          -- The response goes first: when the Sync cycle lasts longer
          -- than the Sync period, a pending Sync is otherwise always
          -- there and responses starve.  Delaying a Sync is harmless,
          -- its T1 is latched at the actual strobe.
          if r.resp_pending then
            rin.state <= ST_RESP;
          elsif r.sync_pending then
            rin.sync_pending <= false;
            rin.t1_wait <= true;
            rin.t1_valid <= false;
            rin.state <= ST_SYNC;
          end if;

        when ST_SYNC =>
          if send_done_s = '1' then
            rin.state <= ST_SYNC_WAIT;
          end if;

        when ST_SYNC_WAIT =>
          -- The strobe always comes: the strober pops one entry per
          -- transmitted frame, in order, so a queued Sync strobes once
          -- the line reaches it.  Giving up on a timer instead would
          -- let the late strobe latch T1 for the next sequence and
          -- pair a Follow_Up with the previous Sync's departure time.
          -- A Sync period shorter than the emission pipeline degrades
          -- to back-to-back Syncs, nothing worse.
          if r.t1_valid then
            rin.state <= ST_FOLLOW_UP;
          end if;

        when ST_FOLLOW_UP =>
          if send_done_s = '1' then
            rin.seq <= r.seq + 1;
            rin.state <= ST_IDLE;
          end if;

        when ST_RESP =>
          if send_done_s = '1' then
            rin.resp_pending <= false;
            rin.state <= ST_IDLE;
          end if;
      end case;

      -- A request landing on the cycle the previous answer completes
      -- takes the slot the answer just freed.
      if msg_valid_s = '1' and not r.msg_ack then
        rin.msg_ack <= true;

        -- One answer is queued at a time: a request arriving while the
        -- previous one is still unanswered is dropped.
        if mt_v = ptp_msg_delay_req_c and not r.resp_pending then
          rin.resp_pending <= true;
          rin.resp_seq <= msg_s.seq;
          rin.resp_id <= msg_s.source_id;
          rin.t4 <= msg_s.capture;
        end if;
      end if;

      if enable_i = '0' then
        rin.sync_pending <= false;
        rin.resp_pending <= false;
        rin.t1_wait <= false;
        rin.t1_valid <= false;

        -- A message being emitted is carried to its last beat: the
        -- stream contract forbids truncating a packet.
        if r.state = ST_SYNC_WAIT then
          rin.state <= ST_IDLE;
        end if;
      end if;
    end process;

    moore: process(r) is
    begin
      send_req_s <= to_logic(r.state = ST_SYNC
                             or r.state = ST_FOLLOW_UP
                             or r.state = ST_RESP);
      msg_ack_s <= to_logic(r.msg_ack);

      tx_req_s.source_id <= r.own_id;

      case r.state is
        when ST_SYNC =>
          tx_req_s.msg_type <= to_byte(ptp_msg_sync_c);
          tx_req_s.seq <= to_be(r.seq);
          tx_req_s.ts <= timestamp_zero_c;
          tx_req_s.req_id <= (others => (others => '0'));
          tx_req_s.strobe <= true;

        when ST_FOLLOW_UP =>
          tx_req_s.msg_type <= to_byte(ptp_msg_follow_up_c);
          tx_req_s.seq <= to_be(r.seq);
          tx_req_s.ts <= r.t1;
          tx_req_s.req_id <= (others => (others => '0'));
          tx_req_s.strobe <= false;

        when others =>
          tx_req_s.msg_type <= to_byte(ptp_msg_delay_resp_c);
          tx_req_s.seq <= r.resp_seq;
          tx_req_s.ts <= r.t4;
          tx_req_s.req_id <= r.resp_id;
          tx_req_s.strobe <= false;
      end case;
    end process;
  end block;

end architecture;
