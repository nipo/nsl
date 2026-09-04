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
use work.mac.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ipv4.all;
use work.stream_udp.all;
use work.stream_dhcp.all;

entity stream_dhcp_client is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    clock_i_hz_c : natural;
    hostname_c : string := ""
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    hwaddr_i : in mac48_t;

    rx_i : in master_t;
    rx_o : out slave_t;
    tx_o : out master_t;
    tx_i : in slave_t;

    address_o : out ipv4_t;
    netmask_o : out ipv4_t;
    router_o : out ipv4_t;
    dns_o : out ipv4_t;
    ntp_server_o : out ipv4_t;
    valid_o : out std_ulogic
    );
end entity;

architecture beh of stream_dhcp_client is

  constant ipv4_any_c : ipv4_t := to_ipv4(0, 0, 0, 0);
  constant ipv4_broadcast_c : ipv4_t := to_ipv4(255, 255, 255, 255);

  -- Byte offsets of the BOOTP fields inside the message.
  constant op_off_c : natural := 0;
  constant htype_off_c : natural := 1;
  constant hlen_off_c : natural := 2;
  constant xid_off_c : natural := 4;
  constant secs_off_c : natural := 8;
  constant flags_off_c : natural := 10;
  constant ciaddr_off_c : natural := 12;
  constant yiaddr_off_c : natural := 16;
  constant chaddr_off_c : natural := 28;
  constant cookie_off_c : natural := dhcp_header_length_c;
  constant options_off_c : natural := cookie_off_c + dhcp_magic_cookie_c'length;

  constant hostname_v : string(1 to hostname_c'length) := hostname_c;
  constant hostname_present_c : boolean := hostname_v'length /= 0;
  constant hostname_size_c : natural
    := 2 * boolean'pos(hostname_present_c) + hostname_v'length;

  -- Option offsets inside the message.  Every message carries the same
  -- layout: the selection options are only meaningful in the request
  -- answering an offer, and are sent as pad options otherwise.
  constant opt_msg_type_off_c : natural := options_off_c;
  constant opt_client_id_off_c : natural := opt_msg_type_off_c + 3;
  constant opt_hostname_off_c : natural := opt_client_id_off_c + 9;
  constant opt_requested_off_c : natural := opt_hostname_off_c + hostname_size_c;
  constant opt_server_id_off_c : natural := opt_requested_off_c + 6;
  constant opt_prl_off_c : natural := opt_server_id_off_c + 6;
  constant opt_end_off_c : natural := opt_prl_off_c + 6;

  constant payload_length_c : natural
    := max(integer_vector'(0 => dhcp_min_payload_length_c,
                           1 => opt_end_off_c + 1));

  constant ctx_size_c : natural
    := context_byte_count(config_c,
                          integer_vector'(0 => ip_context_length_c,
                                          1 => udp_context_length_c));
  constant tx_length_c : natural := ctx_size_c + payload_length_c;

  -- Transported size of the blocks the receive side steps over.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant rx_op_pos_c : natural := pre_size_c + op_off_c;
  constant rx_xid_pos_c : natural := pre_size_c + xid_off_c;
  constant rx_yiaddr_pos_c : natural := pre_size_c + yiaddr_off_c;
  constant rx_cookie_pos_c : natural := pre_size_c + cookie_off_c;
  constant rx_options_pos_c : natural := pre_size_c + options_off_c;

  constant init_delay_c : natural := 1;
  constant discover_period_c : natural := 8;
  constant renew_period_c : natural := 8;
  constant request_timeout_c : natural := 4;
  constant request_retry_c : natural := 4;
  constant timer_max_c : natural := 8;

  type option4_t is
  record
    value: byte_string(0 to 3);
    present: boolean;
  end record;

  constant option4_none_c : option4_t := (
    value => (others => x"00"),
    present => false
    );

  type message_t is
  record
    msg_type: byte;
    msg_type_present: boolean;
    yiaddr: ipv4_t;
    server_id: option4_t;
    netmask: option4_t;
    router: option4_t;
    dns: option4_t;
    ntp_server: option4_t;
    lease: option4_t;
    t1: option4_t;
    t2: option4_t;
  end record;

  constant message_none_c : message_t := (
    msg_type => (others => '0'),
    msg_type_present => false,
    yiaddr => ipv4_any_c,
    server_id => option4_none_c,
    netmask => option4_none_c,
    router => option4_none_c,
    dns => option4_none_c,
    ntp_server => option4_none_c,
    lease => option4_none_c,
    t1 => option4_none_c,
    t2 => option4_none_c
    );

  type tx_request_t is
  record
    msg_type: byte;
    xid: byte_string(0 to 3);
    secs: unsigned(15 downto 0);
    bootp_broadcast: boolean;
    ciaddr: ipv4_t;
    peer: ipv4_t;
    peer_broadcast: boolean;
    selecting: boolean;
    requested: ipv4_t;
    server_id: ipv4_t;
  end record;

  function address_of(o: option4_t) return ipv4_t
  is
  begin
    if o.present then
      return o.value;
    end if;

    return ipv4_any_c;
  end function;

  -- A reply carrying no lease time option is taken as an infinite
  -- lease rather than as an immediate expiry.
  function lease_of(m: message_t) return unsigned
  is
  begin
    if m.lease.present then
      return from_be(m.lease.value);
    end if;

    return x"ffffffff";
  end function;

  function t1_of(m: message_t) return unsigned
  is
  begin
    if m.t1.present then
      return from_be(m.t1.value);
    end if;

    return shift_right(lease_of(m), 1);
  end function;

  function t2_of(m: message_t) return unsigned
  is
  begin
    if m.t2.present then
      return from_be(m.t2.value);
    end if;

    return lease_of(m) - shift_right(lease_of(m), 3);
  end function;

  function payload_byte(req: tx_request_t;
                        hwaddr: mac48_t;
                        pos: natural) return byte
  is
    constant secs_c : byte_string(0 to 1) := to_be(req.secs);
  begin
    if pos = op_off_c then
      return dhcp_op_bootrequest_c;
    elsif pos = htype_off_c then
      return to_byte(1);
    elsif pos = hlen_off_c then
      return to_byte(hwaddr'length);
    elsif pos >= xid_off_c and pos < xid_off_c + 4 then
      return req.xid(pos - xid_off_c);
    elsif pos >= secs_off_c and pos < secs_off_c + 2 then
      return secs_c(pos - secs_off_c);
    elsif pos = flags_off_c then
      if req.bootp_broadcast then
        return to_byte(16#80#);
      end if;
      return to_byte(0);
    elsif pos >= ciaddr_off_c and pos < ciaddr_off_c + 4 then
      return req.ciaddr(pos - ciaddr_off_c);
    elsif pos >= chaddr_off_c and pos < chaddr_off_c + hwaddr'length then
      return hwaddr(pos - chaddr_off_c);
    elsif pos >= cookie_off_c and pos < options_off_c then
      return dhcp_magic_cookie_c(pos - cookie_off_c);
    elsif pos = opt_msg_type_off_c then
      return dhcp_option_message_type_c;
    elsif pos = opt_msg_type_off_c + 1 then
      return to_byte(1);
    elsif pos = opt_msg_type_off_c + 2 then
      return req.msg_type;
    elsif pos = opt_client_id_off_c then
      return dhcp_option_client_id_c;
    elsif pos = opt_client_id_off_c + 1 then
      return to_byte(1 + hwaddr'length);
    elsif pos = opt_client_id_off_c + 2 then
      return to_byte(1);
    elsif pos >= opt_client_id_off_c + 3
      and pos < opt_client_id_off_c + 3 + hwaddr'length then
      return hwaddr(pos - opt_client_id_off_c - 3);
    elsif hostname_present_c and pos = opt_hostname_off_c then
      return dhcp_option_hostname_c;
    elsif hostname_present_c and pos = opt_hostname_off_c + 1 then
      return to_byte(hostname_v'length);
    elsif hostname_present_c
      and pos >= opt_hostname_off_c + 2
      and pos < opt_hostname_off_c + 2 + hostname_v'length then
      return to_byte(hostname_v(pos - opt_hostname_off_c - 1));
    elsif req.selecting and pos = opt_requested_off_c then
      return dhcp_option_requested_address_c;
    elsif req.selecting and pos = opt_requested_off_c + 1 then
      return to_byte(4);
    elsif req.selecting
      and pos >= opt_requested_off_c + 2
      and pos < opt_requested_off_c + 6 then
      return req.requested(pos - opt_requested_off_c - 2);
    elsif req.selecting and pos = opt_server_id_off_c then
      return dhcp_option_server_id_c;
    elsif req.selecting and pos = opt_server_id_off_c + 1 then
      return to_byte(4);
    elsif req.selecting
      and pos >= opt_server_id_off_c + 2
      and pos < opt_server_id_off_c + 6 then
      return req.server_id(pos - opt_server_id_off_c - 2);
    elsif pos = opt_prl_off_c then
      return dhcp_option_parameter_request_c;
    elsif pos = opt_prl_off_c + 1 then
      return to_byte(4);
    elsif pos = opt_prl_off_c + 2 then
      return dhcp_option_netmask_c;
    elsif pos = opt_prl_off_c + 3 then
      return dhcp_option_router_c;
    elsif pos = opt_prl_off_c + 4 then
      return dhcp_option_dns_c;
    elsif pos = opt_prl_off_c + 5 then
      return dhcp_option_ntp_servers_c;
    elsif pos = opt_end_off_c then
      return dhcp_option_end_c;
    end if;

    return to_byte(0);
  end function;

  function tx_byte(req: tx_request_t;
                   hwaddr: mac48_t;
                   pos: natural) return byte_string
  is
    variable ip_ctx: ip_context_t;
    variable udp_ctx: udp_context_t;
    variable ret: byte_string(0 to config_c.data_width-1);
  begin
    ip_ctx.peer := req.peer;
    if req.peer_broadcast then
      ip_ctx.casting := IP_CAST_BROADCAST;
    else
      ip_ctx.casting := IP_CAST_UNICAST;
    end if;
    ip_ctx.length := udp_header_length_c + payload_length_c;
    udp_ctx.peer_port := dhcp_server_port_c;

    if pos < ip_context_length_c then
      ret(0) := to_bytes(ip_ctx)(pos);
    elsif pos < ip_context_length_c + udp_context_length_c then
      ret(0) := to_bytes(udp_ctx)(pos - ip_context_length_c);
    elsif pos < ctx_size_c then
      ret(0) := to_byte(0);
    else
      ret(0) := payload_byte(req, hwaddr, pos - ctx_size_c);
    end if;

    return ret;
  end function;

  signal tick_s : std_ulogic;

  signal send_req_s, send_done_s : std_ulogic;
  signal send_param_s : tx_request_t;

  signal msg_valid_s, msg_ack_s : std_ulogic;
  signal msg_s : message_t;
  signal xid_s : byte_string(0 to 3);

begin

  assert config_c.data_width = 1
    report "DHCP client only supports a byte-wide stream"
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
      hwaddr: mac48_t;
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

    transition: process(r, tx_i, hwaddr_i, send_req_s, send_param_s) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;
          rin.pos <= 0;

        when ST_IDLE =>
          if send_req_s = '1' then
            rin.state <= ST_SEND;
            rin.req <= send_param_s;
            rin.hwaddr <= hwaddr_i;
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
                       bytes => tx_byte(r.req, r.hwaddr, r.pos),
                       user => "0",
                       valid => r.state = ST_SEND,
                       last => r.pos = tx_length_c-1);
      send_done_s <= to_logic(r.state = ST_DONE);
    end process;
  end block;

  receiver: block is
    type state_t is (
      ST_HEAD,
      ST_OPT_CODE,
      ST_OPT_LEN,
      ST_OPT_DATA,
      ST_DRAIN
      );

    type regs_t is
    record
      state: state_t;
      pos: integer range 0 to rx_options_pos_c-1;
      opt_code: byte;
      opt_left: integer range 0 to 255;
      opt_index: integer range 0 to 4;
      ok: boolean;
      rejected: boolean;
      last_seen: boolean;
      parsed: message_t;
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
        r.state <= ST_HEAD;
        r.pos <= 0;
        r.ok <= true;
        r.last_seen <= false;
        r.msg_valid <= false;
        r.parsed <= message_none_c;
      end if;
    end process;

    transition: process(r, rx_i, xid_s, msg_ack_s) is
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
        rin.state <= ST_HEAD;
        rin.pos <= 0;
        rin.ok <= true;
        rin.parsed <= message_none_c;

        if r.ok and not r.rejected and not r.msg_valid
          and r.parsed.msg_type_present
          and (r.state = ST_OPT_CODE or r.state = ST_DRAIN) then
          rin.msg_valid <= true;
          rin.held <= r.parsed;
        end if;
      elsif is_valid(config_c, rx_i) then
        case r.state is
          when ST_HEAD =>
            if r.pos = rx_op_pos_c and rx_data /= dhcp_op_bootreply_c then
              rin.ok <= false;
            end if;

            if r.pos >= rx_xid_pos_c and r.pos < rx_xid_pos_c + 4 then
              if rx_data /= xid_s(r.pos - rx_xid_pos_c) then
                rin.ok <= false;
              end if;
            end if;

            if r.pos >= rx_yiaddr_pos_c and r.pos < rx_yiaddr_pos_c + 4 then
              rin.parsed.yiaddr(r.pos - rx_yiaddr_pos_c) <= rx_data;
            end if;

            if r.pos >= rx_cookie_pos_c and r.pos < rx_options_pos_c then
              if rx_data /= dhcp_magic_cookie_c(r.pos - rx_cookie_pos_c) then
                rin.ok <= false;
              end if;
            end if;

            if r.pos = rx_options_pos_c - 1 then
              rin.state <= ST_OPT_CODE;
            else
              rin.pos <= r.pos + 1;
            end if;

          when ST_OPT_CODE =>
            rin.opt_code <= rx_data;
            if rx_data = dhcp_option_end_c then
              rin.state <= ST_DRAIN;
            elsif rx_data /= dhcp_option_pad_c then
              rin.state <= ST_OPT_LEN;
            end if;

          when ST_OPT_LEN =>
            rin.opt_index <= 0;

            if rx_data = dhcp_option_pad_c then
              rin.state <= ST_OPT_CODE;
            else
              rin.state <= ST_OPT_DATA;
              rin.opt_left <= to_integer(unsigned(rx_data)) - 1;
            end if;

            -- Presence is decided from the announced length, so that an
            -- option carrying a list keeps its first item.
            if r.opt_code = dhcp_option_message_type_c
              and unsigned(rx_data) >= 1 then
              rin.parsed.msg_type_present <= true;
            end if;

            if unsigned(rx_data) >= 4 then
              if r.opt_code = dhcp_option_server_id_c then
                rin.parsed.server_id.present <= true;
              elsif r.opt_code = dhcp_option_netmask_c then
                rin.parsed.netmask.present <= true;
              elsif r.opt_code = dhcp_option_router_c then
                rin.parsed.router.present <= true;
              elsif r.opt_code = dhcp_option_dns_c then
                rin.parsed.dns.present <= true;
              elsif r.opt_code = dhcp_option_ntp_servers_c then
                rin.parsed.ntp_server.present <= true;
              elsif r.opt_code = dhcp_option_lease_time_c then
                rin.parsed.lease.present <= true;
              elsif r.opt_code = dhcp_option_renewal_time_c then
                rin.parsed.t1.present <= true;
              elsif r.opt_code = dhcp_option_rebinding_time_c then
                rin.parsed.t2.present <= true;
              end if;
            end if;

          when ST_OPT_DATA =>
            if r.opt_index < 4 then
              if r.opt_code = dhcp_option_message_type_c then
                rin.parsed.msg_type <= rx_data;
              elsif r.opt_code = dhcp_option_server_id_c then
                rin.parsed.server_id.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_netmask_c then
                rin.parsed.netmask.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_router_c then
                rin.parsed.router.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_dns_c then
                rin.parsed.dns.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_ntp_servers_c then
                rin.parsed.ntp_server.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_lease_time_c then
                rin.parsed.lease.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_renewal_time_c then
                rin.parsed.t1.value(r.opt_index) <= rx_data;
              elsif r.opt_code = dhcp_option_rebinding_time_c then
                rin.parsed.t2.value(r.opt_index) <= rx_data;
              end if;

              rin.opt_index <= r.opt_index + 1;
            end if;

            if r.opt_left = 0 then
              rin.state <= ST_OPT_CODE;
            else
              rin.opt_left <= r.opt_left - 1;
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
      ST_INIT,
      ST_DISCOVER_SEND,
      ST_SELECTING,
      ST_REQUEST_SEND,
      ST_REQUESTING,
      ST_BOUND,
      ST_RENEW_SEND,
      ST_RENEWING,
      ST_REBIND_SEND,
      ST_REBINDING
      );

    type regs_t is
    record
      state: state_t;
      prbs: prbs_state(30 downto 0);
      xid: byte_string(0 to 3);
      secs: unsigned(15 downto 0);
      timer: integer range 0 to timer_max_c;
      retries: integer range 0 to request_retry_c;
      lease, t1, t2: unsigned(31 downto 0);
      offered, address, netmask, router, dns, ntp_server, server_id: ipv4_t;
      valid: boolean;
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
        r.msg_ack <= false;
        r.valid <= false;
      end if;
    end process;

    transition: process(r, enable_i, tick_s, send_done_s,
                        msg_valid_s, msg_s) is
    begin
      rin <= r;

      rin.msg_ack <= false;
      rin.prbs <= prbs_forward(r.prbs, prbs31, 1);

      if tick_s = '1' then
        if r.secs /= x"ffff" then
          rin.secs <= r.secs + 1;
        end if;
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        end if;
        if r.lease /= 0 then
          rin.lease <= r.lease - 1;
        end if;
        if r.t1 /= 0 then
          rin.t1 <= r.t1 - 1;
        end if;
        if r.t2 /= 0 then
          rin.t2 <= r.t2 - 1;
        end if;
      end if;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_INIT;
          rin.timer <= init_delay_c;
          rin.secs <= (others => '0');
          rin.lease <= (others => '0');
          rin.t1 <= (others => '0');
          rin.t2 <= (others => '0');
          rin.valid <= false;

        when ST_IDLE =>
          if enable_i = '1' then
            rin.state <= ST_INIT;
            rin.timer <= init_delay_c;
          end if;

        when ST_INIT =>
          if r.timer = 0 then
            rin.xid <= prbs_byte_string(r.prbs, prbs31, 4);
            rin.secs <= (others => '0');
            rin.state <= ST_DISCOVER_SEND;
          end if;

        when ST_DISCOVER_SEND =>
          if send_done_s = '1' then
            rin.state <= ST_SELECTING;
            rin.timer <= discover_period_c;
          end if;

        when ST_SELECTING =>
          if r.timer = 0 then
            rin.state <= ST_DISCOVER_SEND;
          end if;

        when ST_REQUEST_SEND =>
          if send_done_s = '1' then
            rin.state <= ST_REQUESTING;
            rin.timer <= request_timeout_c;
          end if;

        when ST_REQUESTING =>
          if r.timer = 0 then
            if r.retries /= 0 then
              rin.retries <= r.retries - 1;
              rin.state <= ST_REQUEST_SEND;
            else
              rin.state <= ST_INIT;
              rin.timer <= init_delay_c;
              rin.valid <= false;
            end if;
          end if;

        when ST_BOUND =>
          if r.lease = 0 then
            rin.state <= ST_INIT;
            rin.timer <= init_delay_c;
            rin.valid <= false;
          elsif r.t1 = 0 then
            rin.xid <= prbs_byte_string(r.prbs, prbs31, 4);
            rin.secs <= (others => '0');
            rin.state <= ST_RENEW_SEND;
          end if;

        when ST_RENEW_SEND =>
          if send_done_s = '1' then
            rin.state <= ST_RENEWING;
            rin.timer <= renew_period_c;
          end if;

        when ST_RENEWING =>
          if r.lease = 0 then
            rin.state <= ST_INIT;
            rin.timer <= init_delay_c;
            rin.valid <= false;
          elsif r.t2 = 0 then
            rin.state <= ST_REBIND_SEND;
          elsif r.timer = 0 then
            rin.state <= ST_RENEW_SEND;
          end if;

        when ST_REBIND_SEND =>
          if send_done_s = '1' then
            rin.state <= ST_REBINDING;
            rin.timer <= renew_period_c;
          end if;

        when ST_REBINDING =>
          if r.lease = 0 then
            rin.state <= ST_INIT;
            rin.timer <= init_delay_c;
            rin.valid <= false;
          elsif r.timer = 0 then
            rin.state <= ST_REBIND_SEND;
          end if;
      end case;

      -- A reply can land while a retransmission is being emitted: the
      -- message is left pending through the send states and processed
      -- from the wait state that follows, instead of being consumed
      -- by a state that cannot act on it.
      if msg_valid_s = '1' and not r.msg_ack
        and r.state /= ST_DISCOVER_SEND
        and r.state /= ST_REQUEST_SEND
        and r.state /= ST_RENEW_SEND
        and r.state /= ST_REBIND_SEND then
        rin.msg_ack <= true;

        case r.state is
          when ST_SELECTING =>
            if msg_s.msg_type = dhcp_msg_offer_c
              and msg_s.server_id.present then
              rin.offered <= msg_s.yiaddr;
              rin.server_id <= msg_s.server_id.value;
              rin.netmask <= address_of(msg_s.netmask);
              rin.router <= address_of(msg_s.router);
              rin.dns <= address_of(msg_s.dns);
              rin.ntp_server <= address_of(msg_s.ntp_server);
              rin.lease <= lease_of(msg_s);
              rin.t1 <= t1_of(msg_s);
              rin.t2 <= t2_of(msg_s);
              rin.retries <= request_retry_c;
              rin.state <= ST_REQUEST_SEND;
            end if;

          when ST_REQUESTING =>
            if msg_s.msg_type = dhcp_msg_ack_c then
              rin.address <= msg_s.yiaddr;
              rin.netmask <= address_of(msg_s.netmask);
              rin.router <= address_of(msg_s.router);
              rin.dns <= address_of(msg_s.dns);
              rin.ntp_server <= address_of(msg_s.ntp_server);
              rin.lease <= lease_of(msg_s);
              rin.t1 <= t1_of(msg_s);
              rin.t2 <= t2_of(msg_s);
              rin.valid <= true;
              rin.state <= ST_BOUND;
            elsif msg_s.msg_type = dhcp_msg_nak_c then
              rin.state <= ST_INIT;
              rin.timer <= init_delay_c;
              rin.valid <= false;
            end if;

          when ST_RENEWING | ST_REBINDING =>
            if msg_s.msg_type = dhcp_msg_ack_c then
              rin.address <= msg_s.yiaddr;
              if msg_s.netmask.present then
                rin.netmask <= msg_s.netmask.value;
              end if;
              if msg_s.router.present then
                rin.router <= msg_s.router.value;
              end if;
              if msg_s.dns.present then
                rin.dns <= msg_s.dns.value;
              end if;
              if msg_s.ntp_server.present then
                rin.ntp_server <= msg_s.ntp_server.value;
              end if;
              rin.lease <= lease_of(msg_s);
              rin.t1 <= t1_of(msg_s);
              rin.t2 <= t2_of(msg_s);
              rin.state <= ST_BOUND;
            elsif msg_s.msg_type = dhcp_msg_nak_c then
              rin.state <= ST_INIT;
              rin.timer <= init_delay_c;
              rin.valid <= false;
            end if;

          when others =>
            null;
        end case;
      end if;

      if enable_i = '0' then
        case r.state is
          when ST_DISCOVER_SEND | ST_REQUEST_SEND
            | ST_RENEW_SEND | ST_REBIND_SEND =>
            -- A message being emitted is carried to its last beat: the
            -- stream contract forbids truncating a packet.
            if send_done_s = '1' then
              rin.state <= ST_IDLE;
              rin.valid <= false;
            end if;

          when others =>
            rin.state <= ST_IDLE;
            rin.valid <= false;
        end case;
      end if;
    end process;

    moore: process(r) is
    begin
      send_req_s <= '0';
      send_param_s.msg_type <= dhcp_msg_request_c;
      send_param_s.xid <= r.xid;
      send_param_s.secs <= r.secs;
      send_param_s.bootp_broadcast <= not r.valid;
      send_param_s.ciaddr <= ipv4_any_c;
      send_param_s.peer <= ipv4_broadcast_c;
      send_param_s.peer_broadcast <= true;
      send_param_s.selecting <= false;
      send_param_s.requested <= r.offered;
      send_param_s.server_id <= r.server_id;

      case r.state is
        when ST_DISCOVER_SEND =>
          send_req_s <= '1';
          send_param_s.msg_type <= dhcp_msg_discover_c;

        when ST_REQUEST_SEND =>
          send_req_s <= '1';
          send_param_s.selecting <= true;

        when ST_RENEW_SEND =>
          send_req_s <= '1';
          send_param_s.ciaddr <= r.address;
          send_param_s.peer <= r.server_id;
          send_param_s.peer_broadcast <= false;

        when ST_REBIND_SEND =>
          send_req_s <= '1';
          send_param_s.ciaddr <= r.address;

        when others =>
          null;
      end case;

      msg_ack_s <= to_logic(r.msg_ack);
      xid_s <= r.xid;

      if r.valid then
        address_o <= r.address;
        netmask_o <= r.netmask;
        router_o <= r.router;
        dns_o <= r.dns;
        ntp_server_o <= r.ntp_server;
      else
        address_o <= ipv4_any_c;
        netmask_o <= ipv4_any_c;
        router_o <= ipv4_any_c;
        dns_o <= ipv4_any_c;
        ntp_server_o <= ipv4_any_c;
      end if;
      valid_o <= to_logic(r.valid);
    end process;
  end block;

end architecture;
