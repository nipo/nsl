library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ethernet.all;
use work.stream_ipv4.all;

entity stream_arp_resolver is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    cache_count_l2_c : natural := 3;
    timeout_c : natural := 125000000;
    retry_count_c : natural := 3
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_hwaddr_i : in mac48_t;
    local_address_i : in ipv4_t;
    netmask_i : in ipv4_t := to_ipv4(0, 0, 0, 0);
    gateway_i : in ipv4_t := to_ipv4(0, 0, 0, 0);

    l1_header_i : in byte_string;

    -- Ethernet layer 0x0806 pipe
    from_l2_i : in master_t;
    from_l2_o : out slave_t;
    to_l2_o : out master_t;
    to_l2_i : in slave_t;

    query_i : in master_t;
    query_o : out slave_t;

    response_o : out master_t;
    response_i : in slave_t
    );
end entity;

-- The component is made of three cooperating state machines sharing
-- one register set: the ethernet-side receiver, the ethernet-side
-- transmitter, and the resolver serving queries.
--
-- The cache holds 2**cache_count_l2_c entries in registers.  An
-- address already present is refreshed in place; a new address takes
-- the entry designated by a round-robin pointer, so the table holds
-- the most recently learnt addresses whatever their usage.  Entries
-- never expire: a stale entry only heals when its peer talks to us
-- again.
--
-- A query for a peer outside the local subnet resolves against
-- gateway_i instead: the diversion is decided as the query context
-- is parsed, and only the lookup target changes.  The query block
-- itself is echoed as received, so the client still addresses the
-- original peer at layer 3.
--
-- Both the reply to a peer request and the request of a pending
-- resolution reach the wire through the transmitter, which serves
-- one frame at a time, replies first.  The receiver holds its input
-- ready low while a reply it decided upon waits for the
-- transmitter, so no reply is ever lost.
--
-- The associative compares against the cache, the parsing of a
-- received payload and the zero test of the retry counter are all
-- registered one cycle ahead of the machine that consumes them, so
-- that no compare cone reaches a decision.  In the same spirit, the
-- layer-2 context a query resolves to is registered by the state
-- that decides it, and the response is assembled from that register
-- one cycle later: whichever way a query is answered, the answer
-- travels through the same single register-to-register hop.  This
-- costs one cycle between the end of a frame and its effects, and
-- two cycles between a query and its response, which is free at ARP
-- timescales.
architecture beh of stream_arp_resolver is

  constant width_c : natural := config_c.data_width;
  -- Transported size of the blocks of the layers below, forwarded
  -- verbatim in front of every ethernet frame and every response.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant l2_block_c : natural
    := context_byte_count(config_c, (0 => l2_context_length_c));
  constant ip_block_c : natural
    := context_byte_count(config_c, (0 => ip_context_length_c));
  constant arp_pdu_length_c : natural := 28;

  -- The ARP payload sits at a fixed offset of the ethernet-side
  -- streams, past the forwarded blocks and the layer-2 context
  -- block.  Both are a whole count of beats, and the payload length
  -- is a multiple of every supported width, so payload beats are
  -- aligned on both sides.
  constant rx_pdu_beat_c : natural := (pre_size_c + l2_block_c) / width_c;
  constant pdu_beats_c : natural := arp_pdu_length_c / width_c;

  constant tx_length_c : natural
    := pre_size_c + l2_block_c + arp_pdu_length_c;
  constant tx_beats_c : natural := tx_length_c / width_c;

  constant resp_length_c : natural := pre_size_c + l2_block_c + ip_block_c;
  constant resp_beats_c : natural := resp_length_c / width_c;
  constant query_beats_c : natural := ip_block_c / width_c;

  constant cache_count_c : natural := 2 ** cache_count_l2_c;

  -- ARP payload for IPv4 over ethernet, field offsets in the 28-byte
  -- payload:
  -- * hardware type [0 to 1], protocol type [2 to 3]
  -- * hardware length [4], protocol length [5]
  -- * operation [6 to 7]
  -- * sender hardware address [8 to 13], sender protocol address [14 to 17]
  -- * target hardware address [18 to 23], target protocol address [24 to 27]
  constant arp_htype_c : byte_string(0 to 1) := from_hex("0001");
  constant arp_ptype_c : byte_string(0 to 1) := from_hex("0800");
  constant arp_hlen_c : byte := to_byte(6);
  constant arp_plen_c : byte := to_byte(4);
  constant arp_oper_request_c : byte_string(0 to 1) := from_hex("0001");
  constant arp_oper_reply_c : byte_string(0 to 1) := from_hex("0002");

  constant mac_null_c : mac48_t := (others => x"00");
  constant ipv4_null_c : ipv4_t := (others => x"00");
  constant l2_null_c : byte_string(0 to l2_context_length_c-1)
    := (others => x"00");

  -- A zero netmask disables the test altogether, so that a station
  -- with no subnet configured treats every peer as on-link.
  function off_subnet(peer, address, netmask: ipv4_t) return boolean
  is
  begin
    return netmask /= ipv4_null_c
      and ((peer xor address) and netmask) /= ipv4_null_c;
  end function;

  function arp_pdu(oper: byte_string;
                   sha: mac48_t; spa: ipv4_t;
                   tha: mac48_t; tpa: ipv4_t) return byte_string
  is
  begin
    return arp_htype_c & arp_ptype_c & arp_hlen_c & arp_plen_c
      & oper & sha & spa & tha & tpa;
  end function;

  type lookup_t is
  record
    hit: boolean;
    index: natural range 0 to cache_count_c-1;
  end record;

  function cache_lookup(address: ipv4_vector;
                        valid: std_ulogic_vector;
                        target: ipv4_t) return lookup_t
  is
    variable ret: lookup_t := (hit => false, index => 0);
  begin
    for i in 0 to cache_count_c-1
    loop
      if valid(i) = '1' and address(i) = target then
        ret.hit := true;
        ret.index := i;
      end if;
    end loop;
    return ret;
  end function;

  type match_t is
  record
    hit: boolean;
    hwaddr: mac48_t;
  end record;

  -- Carries the matched hardware address rather than its index, so
  -- that a match latched one cycle ahead of its use survives the
  -- recycling of the entry it came from.
  function cache_match(address: ipv4_vector;
                       hwaddr: mac48_vector;
                       valid: std_ulogic_vector;
                       target: ipv4_t) return match_t
  is
    variable ret: match_t := (hit => false, hwaddr => mac_null_c);
  begin
    for i in 0 to cache_count_c-1
    loop
      if valid(i) = '1' and address(i) = target then
        ret.hit := true;
        ret.hwaddr := hwaddr(i);
      end if;
    end loop;
    return ret;
  end function;

  type rx_state_t is (
    RX_RESET,
    -- Skipping the blocks preceding the ARP payload
    RX_HEADER,
    -- Latching the ARP payload
    RX_PDU,
    -- Skipping whatever follows the payload, mac padding included
    RX_TAIL,
    -- Letting the payload parsing and the cache lookup of the
    -- complete frame reach their registers
    RX_DECIDE,
    -- Deciding on a complete frame
    RX_COMMIT,
    -- Handing a reply to the transmitter
    RX_REPLY
    );

  type tx_state_t is (
    TX_RESET,
    TX_IDLE,
    TX_SEND
    );

  type resolve_state_t is (
    RESOLVE_RESET,
    -- Latching the query block
    RESOLVE_RECEIVE,
    -- Casting decision and peer latching
    RESOLVE_DECIDE,
    -- Letting the cache lookup of the freshly latched peer reach its
    -- register
    RESOLVE_SETTLE,
    -- Looking the peer up in the cache
    RESOLVE_LOOKUP,
    -- Handing a request to the transmitter
    RESOLVE_REQUEST,
    -- Waiting for the peer to be learnt, or for the retry timeout
    RESOLVE_WAIT,
    -- Assembling the response from the decided layer-2 context
    RESOLVE_BUILD,
    RESOLVE_RESPOND
    );

  -- States where the ethernet-side and query-side inputs are
  -- consumed, shared by the transition and the moore processes.
  function rx_accepting(state: rx_state_t) return boolean
  is
  begin
    return state = RX_HEADER or state = RX_PDU or state = RX_TAIL;
  end function;

  function resolve_accepting(state: resolve_state_t) return boolean
  is
  begin
    return state = RESOLVE_RECEIVE;
  end function;

  type regs_t is
  record
    cache_address: ipv4_vector(0 to cache_count_c-1);
    cache_hwaddr: mac48_vector(0 to cache_count_c-1);
    cache_valid: std_ulogic_vector(0 to cache_count_c-1);
    cache_next: natural range 0 to cache_count_c-1;

    rx_state: rx_state_t;
    rx_left: natural range 0 to rx_pdu_beat_c + pdu_beats_c;
    rx_pdu: byte_string(0 to arp_pdu_length_c-1);
    rx_rejected: boolean;
    rx_peer_hwaddr: mac48_t;
    rx_peer_address: ipv4_t;
    -- Payload parsing and cache lookup of the received frame, one
    -- cycle behind rx_pdu, only meaningful in RX_COMMIT
    rx_usable: boolean;
    rx_is_request: boolean;
    rx_learnt: boolean;
    rx_slot: natural range 0 to cache_count_c-1;

    tx_state: tx_state_t;
    tx_data: byte_string(0 to tx_length_c-1);
    tx_left: natural range 0 to tx_beats_c;

    resolve_state: resolve_state_t;
    resolve_left: natural range 0 to query_beats_c + resp_beats_c;
    resolve_query: byte_string(0 to ip_block_c-1);
    -- Address the resolution runs against: the queried peer, or the
    -- gateway when the peer sits outside the local subnet
    resolve_target: ipv4_t;
    -- Layer-2 context block the query resolved to, as decided by
    -- RESOLVE_DECIDE, RESOLVE_LOOKUP or RESOLVE_WAIT
    resolve_l2: byte_string(0 to l2_context_length_c-1);
    resolve_response: byte_string(0 to resp_length_c-1);
    resolve_rejected: boolean;
    resolve_timeout: natural range 0 to timeout_c-1;
    resolve_retry: natural range 0 to retry_count_c;
    -- Cache lookup of resolve_target, one cycle behind the cache and
    -- behind resolve_target
    resolve_match: boolean;
    resolve_match_hwaddr: mac48_t;
    -- Zero test of resolve_timeout, one cycle behind the counter
    resolve_expired: boolean;
  end record;

  signal r, rin: regs_t;

begin

  assert pre_size_c = 0 or l1_header_i'length = pre_size_c
    report "l1_header_i must carry the transported size of the"
    & " header_length_c blocks"
    severity failure;

  assert timeout_c > 0
    report "Retry timeout must be at least one cycle"
    severity failure;

  assert arp_pdu_length_c mod width_c = 0
    report "Stream width must divide the ARP payload length"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.rx_state <= RX_RESET;
      r.tx_state <= TX_RESET;
      r.resolve_state <= RESOLVE_RESET;
      r.cache_valid <= (others => '0');
      r.cache_next <= 0;
    end if;
  end process;

  transition: process(r, from_l2_i, to_l2_i, query_i, response_i,
                      local_hwaddr_i, local_address_i, netmask_i, gateway_i,
                      l1_header_i) is
    -- Parsed contents of the last received ARP payload, latched at
    -- the end of the process, only meaningful one cycle later
    variable rx_sha_v: mac48_t;
    variable rx_spa_v: ipv4_t;
    variable rx_usable_v, rx_is_request_v: boolean;
    variable rx_learn_v: lookup_t;

    -- Transmitter arbitration, replies before requests
    variable tx_reply_v, tx_request_v: boolean;

    variable query_context_v: ip_context_t;
    -- Address the query resolves against, latched by RESOLVE_DECIDE
    variable query_target_v: ipv4_t;
    variable resolve_match_v: match_t;
  begin
    rin <= r;

    rx_sha_v := r.rx_pdu(8 to 13);
    rx_spa_v := r.rx_pdu(14 to 17);
    rx_is_request_v := r.rx_pdu(6 to 7) = arp_oper_request_c;
    -- A frame is only acted upon when it is an IPv4-over-ethernet
    -- ARP request or reply targeting the local station and its last
    -- beat did not carry the reject flag.
    rx_usable_v := not r.rx_rejected
                   and r.rx_pdu(0 to 1) = arp_htype_c
                   and r.rx_pdu(2 to 3) = arp_ptype_c
                   and r.rx_pdu(4) = arp_hlen_c
                   and r.rx_pdu(5) = arp_plen_c
                   and (rx_is_request_v
                        or r.rx_pdu(6 to 7) = arp_oper_reply_c)
                   and r.rx_pdu(24 to 27) = local_address_i;
    rx_learn_v := cache_lookup(r.cache_address, r.cache_valid, rx_spa_v);

    -- Both compare cones are latched here unconditionally; the state
    -- machines only ever look at the registered result, one cycle
    -- after the operands they depend upon have settled.
    rin.rx_usable <= rx_usable_v;
    rin.rx_is_request <= rx_is_request_v;
    rin.rx_learnt <= rx_learn_v.hit;
    if rx_learn_v.hit then
      rin.rx_slot <= rx_learn_v.index;
    else
      rin.rx_slot <= r.cache_next;
    end if;

    resolve_match_v := cache_match(r.cache_address, r.cache_hwaddr,
                                   r.cache_valid, r.resolve_target);
    rin.resolve_match <= resolve_match_v.hit;
    rin.resolve_match_hwaddr <= resolve_match_v.hwaddr;

    tx_reply_v := r.tx_state = TX_IDLE and r.rx_state = RX_REPLY;
    tx_request_v := r.tx_state = TX_IDLE and not tx_reply_v
                    and r.resolve_state = RESOLVE_REQUEST;

    query_context_v := from_bytes(r.resolve_query(0 to ip_context_length_c-1));
    if off_subnet(query_context_v.peer, local_address_i, netmask_i) then
      query_target_v := gateway_i;
    else
      query_target_v := query_context_v.peer;
    end if;

    case r.rx_state is
      when RX_RESET =>
        rin.rx_state <= RX_HEADER;
        rin.rx_left <= rx_pdu_beat_c - 1;

      when RX_HEADER =>
        if is_valid(config_c, from_l2_i) then
          rin.rx_rejected <= is_rejected(config_c, from_l2_i);
          if is_last(config_c, from_l2_i) then
            -- Frame ends before the ARP payload, nothing to decide
            rin.rx_state <= RX_RESET;
          elsif r.rx_left /= 0 then
            rin.rx_left <= r.rx_left - 1;
          else
            rin.rx_state <= RX_PDU;
            rin.rx_left <= pdu_beats_c - 1;
          end if;
        end if;

      when RX_PDU =>
        if is_valid(config_c, from_l2_i) then
          rin.rx_pdu <= r.rx_pdu(width_c to arp_pdu_length_c-1)
                        & bytes(config_c, from_l2_i);
          rin.rx_rejected <= is_rejected(config_c, from_l2_i);

          if is_last(config_c, from_l2_i)
            and (r.rx_left /= 0
                 or byte_count(config_c, from_l2_i) /= width_c) then
            -- Frame ends inside the ARP payload
            rin.rx_state <= RX_RESET;
          elsif r.rx_left /= 0 then
            rin.rx_left <= r.rx_left - 1;
          elsif is_last(config_c, from_l2_i) then
            rin.rx_state <= RX_DECIDE;
          else
            rin.rx_state <= RX_TAIL;
          end if;
        end if;

      when RX_TAIL =>
        if is_valid(config_c, from_l2_i) then
          rin.rx_rejected <= is_rejected(config_c, from_l2_i);
          if is_last(config_c, from_l2_i) then
            rin.rx_state <= RX_DECIDE;
          end if;
        end if;

      when RX_DECIDE =>
        rin.rx_state <= RX_COMMIT;

      when RX_COMMIT =>
        rin.rx_state <= RX_RESET;

        if r.rx_usable then
          rin.cache_address(r.rx_slot) <= rx_spa_v;
          rin.cache_hwaddr(r.rx_slot) <= rx_sha_v;
          rin.cache_valid(r.rx_slot) <= '1';
          if not r.rx_learnt then
            if r.cache_next = cache_count_c-1 then
              rin.cache_next <= 0;
            else
              rin.cache_next <= r.cache_next + 1;
            end if;
          end if;

          if r.rx_is_request then
            rin.rx_peer_hwaddr <= rx_sha_v;
            rin.rx_peer_address <= rx_spa_v;
            rin.rx_state <= RX_REPLY;
          end if;
        end if;

      when RX_REPLY =>
        if tx_reply_v then
          rin.rx_state <= RX_RESET;
        end if;
    end case;

    case r.tx_state is
      when TX_RESET =>
        rin.tx_state <= TX_IDLE;

      when TX_IDLE =>
        if tx_reply_v then
          rin.tx_data
            <= context_head(l1_header_i, pre_size_c)
            & context_pad(config_c,
                          to_bytes(l2_context_t'(peer => r.rx_peer_hwaddr,
                                                 casting => L2_CAST_UNICAST)))
            & arp_pdu(oper => arp_oper_reply_c,
                      sha => local_hwaddr_i, spa => local_address_i,
                      tha => r.rx_peer_hwaddr, tpa => r.rx_peer_address);
          rin.tx_state <= TX_SEND;
          rin.tx_left <= tx_beats_c - 1;
        elsif tx_request_v then
          rin.tx_data
            <= context_head(l1_header_i, pre_size_c)
            & context_pad(config_c,
                          to_bytes(l2_context_t'(peer => ethernet_broadcast_addr_c,
                                                 casting => L2_CAST_BROADCAST)))
            & arp_pdu(oper => arp_oper_request_c,
                      sha => local_hwaddr_i, spa => local_address_i,
                      tha => mac_null_c, tpa => r.resolve_target);
          rin.tx_state <= TX_SEND;
          rin.tx_left <= tx_beats_c - 1;
        end if;

      when TX_SEND =>
        if is_ready(config_c, to_l2_i) then
          if r.tx_left /= 0 then
            rin.tx_left <= r.tx_left - 1;
            rin.tx_data(0 to tx_length_c-1-width_c)
              <= r.tx_data(width_c to tx_length_c-1);
          else
            rin.tx_state <= TX_IDLE;
          end if;
        end if;
    end case;

    case r.resolve_state is
      when RESOLVE_RESET =>
        rin.resolve_state <= RESOLVE_RECEIVE;
        rin.resolve_left <= query_beats_c - 1;

      when RESOLVE_RECEIVE =>
        if is_valid(config_c, query_i) then
          rin.resolve_query <= r.resolve_query(width_c to ip_block_c-1)
                               & bytes(config_c, query_i);

          if r.resolve_left /= 0 then
            rin.resolve_left <= r.resolve_left - 1;
          else
            rin.resolve_state <= RESOLVE_DECIDE;
          end if;
        end if;

      when RESOLVE_DECIDE =>
        if query_context_v.casting = IP_CAST_BROADCAST then
          -- A broadcast peer needs no lookup at all
          rin.resolve_l2
            <= to_bytes(l2_context_t'(peer => ethernet_broadcast_addr_c,
                                      casting => L2_CAST_BROADCAST));
          rin.resolve_rejected <= false;
          rin.resolve_state <= RESOLVE_BUILD;
        else
          rin.resolve_target <= query_target_v;
          rin.resolve_retry <= retry_count_c;
          rin.resolve_state <= RESOLVE_SETTLE;
        end if;

      when RESOLVE_SETTLE =>
        rin.resolve_state <= RESOLVE_LOOKUP;

      when RESOLVE_LOOKUP =>
        if r.resolve_match then
          rin.resolve_l2
            <= to_bytes(l2_context_t'(peer => r.resolve_match_hwaddr,
                                      casting => L2_CAST_UNICAST));
          rin.resolve_rejected <= false;
          rin.resolve_state <= RESOLVE_BUILD;
        else
          rin.resolve_state <= RESOLVE_REQUEST;
        end if;

      when RESOLVE_REQUEST =>
        if tx_request_v then
          rin.resolve_timeout <= timeout_c - 1;
          rin.resolve_expired <= (timeout_c <= 1);
          rin.resolve_state <= RESOLVE_WAIT;
        end if;

      when RESOLVE_WAIT =>
        if r.resolve_match then
          rin.resolve_l2
            <= to_bytes(l2_context_t'(peer => r.resolve_match_hwaddr,
                                      casting => L2_CAST_UNICAST));
          rin.resolve_rejected <= false;
          rin.resolve_state <= RESOLVE_BUILD;
        elsif not r.resolve_expired then
          rin.resolve_timeout <= r.resolve_timeout - 1;
          rin.resolve_expired <= (r.resolve_timeout = 1);
        elsif r.resolve_retry /= 0 then
          rin.resolve_retry <= r.resolve_retry - 1;
          rin.resolve_state <= RESOLVE_REQUEST;
        else
          -- Retries exhausted, the query gets a rejected response
          -- with a zeroed layer-2 context block
          rin.resolve_l2 <= l2_null_c;
          rin.resolve_rejected <= true;
          rin.resolve_state <= RESOLVE_BUILD;
        end if;

      when RESOLVE_BUILD =>
        rin.resolve_response <= context_head(l1_header_i, pre_size_c)
                                & context_pad(config_c, r.resolve_l2)
                                & r.resolve_query;
        rin.resolve_left <= resp_beats_c - 1;
        rin.resolve_state <= RESOLVE_RESPOND;

      when RESOLVE_RESPOND =>
        if is_ready(config_c, response_i) then
          if r.resolve_left /= 0 then
            rin.resolve_left <= r.resolve_left - 1;
            rin.resolve_response(0 to resp_length_c-1-width_c)
              <= r.resolve_response(width_c to resp_length_c-1);
          else
            rin.resolve_state <= RESOLVE_RESET;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable user_v: std_ulogic_vector(0 to 0);
  begin
    from_l2_o <= accept(config_c, rx_accepting(r.rx_state));
    query_o <= accept(config_c, resolve_accepting(r.resolve_state));

    if r.tx_state = TX_SEND then
      to_l2_o <= transfer(config_c,
                          bytes => r.tx_data(0 to width_c-1),
                          user => "0",
                          valid => true,
                          last => r.tx_left = 0);
    else
      to_l2_o <= transfer_defaults(config_c);
    end if;

    if r.resolve_state = RESOLVE_RESPOND then
      user_v := (0 => to_logic(r.resolve_rejected and r.resolve_left = 0));
      response_o <= transfer(config_c,
                             bytes => r.resolve_response(0 to width_c-1),
                             user => user_v,
                             valid => true,
                             last => r.resolve_left = 0);
    else
      response_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
