library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ipv4.all;
use work.stream_udp.all;
use work.stream_sntp.all;

entity stream_sntp_client is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    clock_i_hz_c : natural;
    poll_period_c : natural := 64
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    server_i : in ipv4_t;
    server_valid_i : in std_ulogic := '1';

    rx_i : in master_t;
    rx_o : out slave_t;
    tx_o : out master_t;
    tx_i : in slave_t;

    time_o : out unsigned(63 downto 0);
    tick_o : out std_ulogic;
    valid_o : out std_ulogic
    );
end entity;

architecture beh of stream_sntp_client is

  constant timestamp_length_c : natural := 8;

  -- LI 0, VN 4, mode 3
  constant client_flags_c : byte := to_byte(16#23#);
  constant server_mode_c : std_ulogic_vector(2 downto 0) := "100";
  constant version3_c : std_ulogic_vector(2 downto 0) := "011";
  constant version4_c : std_ulogic_vector(2 downto 0) := "100";
  constant stratum_max_c : natural := 15;

  constant init_delay_c : natural := 1;
  constant retry_period_c : natural := 8;
  constant timer_max_c : natural
    := max(integer_vector'(0 => init_delay_c,
                           1 => retry_period_c,
                           2 => poll_period_c));

  constant ctx_size_c : natural
    := context_byte_count(config_c,
                          integer_vector'(0 => ip_context_length_c,
                                          1 => udp_context_length_c));
  constant tx_length_c : natural := ctx_size_c + sntp_message_length_c;

  -- Transported size of the blocks the receive side steps over.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant rx_flags_pos_c : natural := pre_size_c + sntp_flags_offset_c;
  constant rx_stratum_pos_c : natural := pre_size_c + sntp_stratum_offset_c;
  constant rx_originate_pos_c : natural
    := pre_size_c + sntp_originate_ts_offset_c;
  constant rx_transmit_pos_c : natural
    := pre_size_c + sntp_transmit_ts_offset_c;
  constant rx_end_pos_c : natural := pre_size_c + sntp_message_length_c;

  subtype timestamp_t is byte_string(0 to timestamp_length_c-1);

  type tx_request_t is
  record
    peer: ipv4_t;
    nonce: timestamp_t;
  end record;

  function message_byte(req: tx_request_t; pos: natural) return byte
  is
  begin
    if pos = sntp_flags_offset_c then
      return client_flags_c;
    elsif pos >= sntp_transmit_ts_offset_c
      and pos < sntp_transmit_ts_offset_c + timestamp_length_c then
      return req.nonce(pos - sntp_transmit_ts_offset_c);
    end if;

    return to_byte(0);
  end function;

  function tx_byte(req: tx_request_t; pos: natural) return byte_string
  is
    variable ip_ctx: ip_context_t;
    variable udp_ctx: udp_context_t;
    variable ret: byte_string(0 to config_c.data_width-1);
  begin
    ip_ctx.peer := req.peer;
    ip_ctx.casting := IP_CAST_UNICAST;
    ip_ctx.length := udp_header_length_c + sntp_message_length_c;
    udp_ctx.peer_port := sntp_port_c;

    if pos < ip_context_length_c then
      ret(0) := to_bytes(ip_ctx)(pos);
    elsif pos < ip_context_length_c + udp_context_length_c then
      ret(0) := to_bytes(udp_ctx)(pos - ip_context_length_c);
    elsif pos < ctx_size_c then
      ret(0) := to_byte(0);
    else
      ret(0) := message_byte(req, pos - ctx_size_c);
    end if;

    return ret;
  end function;

  signal tick_s : std_ulogic;

  signal send_req_s, send_done_s : std_ulogic;

  signal msg_valid_s, msg_ack_s : std_ulogic;
  signal msg_s : unsigned(63 downto 0);
  signal nonce_s : timestamp_t;

begin

  assert config_c.data_width = 1
    report "SNTP client only supports a byte-wide stream"
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

    transition: process(r, tx_i, server_i, send_req_s, nonce_s) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.pos <= 0;

        when ST_IDLE =>
          if send_req_s = '1' then
            rin.state <= ST_SEND;
            rin.req.peer <= server_i;
            rin.req.nonce <= nonce_s;
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
      pos: integer range 0 to rx_end_pos_c-1;
      ok: boolean;
      rejected: boolean;
      last_seen: boolean;
      parsed: timestamp_t;
      held: unsigned(63 downto 0);
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
        r.ok <= true;
        r.rejected <= false;
        r.last_seen <= false;
        r.msg_valid <= false;
        r.held <= (others => '0');
      end if;
    end process;

    transition: process(r, rx_i, nonce_s, msg_ack_s) is
      variable rx_data: byte;
    begin
      rin <= r;
      rx_data := bytes(config_c, rx_i)(0);

      if msg_ack_s = '1' then
        rin.msg_valid <= false;
      end if;

      if r.last_seen then
        -- Decision cycle: the parse state has settled and the input is
        -- held off for this single beat.
        rin.last_seen <= false;
        rin.state <= ST_MESSAGE;
        rin.pos <= 0;
        rin.ok <= true;

        if r.ok and not r.rejected and not r.msg_valid
          and r.state = ST_DRAIN then
          rin.msg_valid <= true;
          rin.held <= from_be(r.parsed);
        end if;
      elsif is_valid(config_c, rx_i) then
        case r.state is
          when ST_MESSAGE =>
            if r.pos = rx_flags_pos_c then
              if rx_data(2 downto 0) /= server_mode_c then
                rin.ok <= false;
              end if;

              if rx_data(5 downto 3) /= version3_c
                and rx_data(5 downto 3) /= version4_c then
                rin.ok <= false;
              end if;
            end if;

            if r.pos = rx_stratum_pos_c then
              if unsigned(rx_data) = 0
                or unsigned(rx_data) > stratum_max_c then
                rin.ok <= false;
              end if;
            end if;

            if r.pos >= rx_originate_pos_c
              and r.pos < rx_originate_pos_c + timestamp_length_c then
              if rx_data /= nonce_s(r.pos - rx_originate_pos_c) then
                rin.ok <= false;
              end if;
            end if;

            if r.pos >= rx_transmit_pos_c
              and r.pos < rx_transmit_pos_c + timestamp_length_c then
              rin.parsed(r.pos - rx_transmit_pos_c) <= rx_data;
            end if;

            if r.pos = rx_end_pos_c-1 then
              rin.state <= ST_DRAIN;
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
  end block;

  client: block is
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_WAIT,
      ST_SEND
      );

    type regs_t is
    record
      state: state_t;
      prbs: prbs_state(30 downto 0);
      nonce: timestamp_t;
      timer: integer range 0 to timer_max_c;
      seconds: unsigned(31 downto 0);
      fraction: unsigned(31 downto 0);
      valid: boolean;
      tick: std_ulogic;
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
        r.prbs <= (others => '1');
        r.tick <= '0';
        r.msg_ack <= false;
        r.valid <= false;
      end if;
    end process;

    transition: process(r, enable_i, server_valid_i, tick_s, send_done_s,
                        msg_valid_s, msg_s) is
      variable gate_v: boolean;
    begin
      rin <= r;
      gate_v := enable_i = '1' and server_valid_i = '1';

      rin.msg_ack <= false;
      rin.tick <= '0';
      rin.prbs <= prbs_forward(r.prbs, prbs31, 1);

      if tick_s = '1' then
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        end if;

        if r.valid then
          rin.seconds <= r.seconds + 1;
          rin.tick <= '1';
        end if;
      end if;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.timer <= 0;
          rin.seconds <= (others => '0');
          rin.fraction <= (others => '0');
          rin.valid <= false;

        when ST_IDLE =>
          if gate_v then
            rin.state <= ST_WAIT;
            rin.timer <= init_delay_c;
          end if;

        when ST_WAIT =>
          if r.timer = 0 then
            rin.nonce <= prbs_byte_string(r.prbs, prbs31, timestamp_length_c);
            rin.state <= ST_SEND;
          end if;

        when ST_SEND =>
          if send_done_s = '1' then
            rin.state <= ST_WAIT;
            if r.valid then
              rin.timer <= poll_period_c;
            else
              rin.timer <= retry_period_c;
            end if;
          end if;
      end case;

      -- A reply can land while a request is being emitted: the message
      -- is left pending through the send state and processed from the
      -- wait state that follows, instead of being consumed by a state
      -- that cannot act on it.
      if msg_valid_s = '1' and not r.msg_ack and r.state = ST_WAIT then
        rin.msg_ack <= true;
        rin.seconds <= msg_s(63 downto 32);
        rin.fraction <= msg_s(31 downto 0);
        rin.timer <= poll_period_c;
        rin.valid <= true;
      end if;

      if not gate_v then
        case r.state is
          when ST_SEND =>
            -- A request being emitted is carried to its last beat: the
            -- stream contract forbids truncating a packet.
            if send_done_s = '1' then
              rin.state <= ST_IDLE;
              rin.tick <= '0';
              rin.valid <= false;
            end if;

          when others =>
            rin.state <= ST_IDLE;
            rin.tick <= '0';
            rin.valid <= false;
        end case;
      end if;
    end process;

    moore: process(r) is
    begin
      send_req_s <= to_logic(r.state = ST_SEND);
      nonce_s <= r.nonce;
      msg_ack_s <= to_logic(r.msg_ack);

      if r.valid then
        time_o(63 downto 32) <= r.seconds;
        time_o(31 downto 0) <= r.fraction;
      else
        time_o <= (others => '0');
      end if;
      tick_o <= r.tick;
      valid_o <= to_logic(r.valid);
    end process;
  end block;

end architecture;
