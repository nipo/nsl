library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Cache entry (11 bytes, rounded to 16)
-- - IP (4 byte)
-- - Mac (6 bytes)
-- - TTL (1 byte)
--
-- Table is stupid and unsorted. Search time is crap.

-- Automatons:
--
-- 1- Cache lookup (lookup_*)
--
--    Read access to cache memory, asynchronous Can end up in Miss
--    state, waits for requester to be sent. A cache miss drops the
--    packet TX. Sender may retry cache lookup once response arrived
--    (but is not informed of such condition).
--
--    Orders taken from: L2 lookup
--    Reads: Cache storage
--    Queries to: Sender
--
-- 2- Sender (sender_*)
--
--    When cache miss happens, tells response handler to prepare a
--    cache entry for the target and sends probe to the network.
--
--    Orders taken from: Cache lookup (for requests), Receiver (for responses)
--    Queries to: Network
--
-- 3- Receiver (receiver_*)
--
--    Monitors incoming responses packet to update cache, filters
--    requests.  Has write port to the cache.  Also decays TTL of
--    cache.
--
--    Orders taken from: Network, TTL refresh timeout
--    Read/Write: Cache storage

library nsl_bnoc, work, nsl_data, nsl_memory, nsl_math, nsl_logic;
use work.ethernet.all;
use work.ipv4.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity arp_ethernet is
  generic(
    -- L2 header length is fixed by MAC layer
    header_length_c : integer := 0;
    cache_count_c : integer := 1;
    clock_i_hz_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Layer-1/2 header, supposed to be fixed, if any.
    header_i : in byte_string(0 to header_length_c-1) := (others => x"00");

    -- Host configuration
    unicast_i : in ipv4_t;
    netmask_i : in ipv4_t := (others => x"ff");
    gateway_i : in ipv4_t := (others => x"00");
    hwaddr_i : in mac48_t;

    -- Layer 2 link
    to_l2_o : out committed_req;
    to_l2_i : in committed_ack;
    from_l2_i : in committed_req;
    from_l2_o : out committed_ack;

    -- Rx notification API
    -- header | mac | context | ipv4 | context
    notify_i : in byte_string(0 to header_length_c+7+4) := (others => x"00");
    notify_valid_i : in std_ulogic := '0';

    -- Resolver API for IP usage
    request_i : in framed_req;
    request_o : out framed_ack;
    response_o : out framed_req;
    response_i : in framed_ack
    );
end entity;

architecture beh of arp_ethernet is

  constant ticker_hz_c : integer := 8;
  constant query_timeout_c : integer := 3;
  constant ttl_c : integer := 16;
  constant ttl_init_value_c : integer := ttl_c * ticker_hz_c - 1;

  -- RFC Opcodes
  constant operation_request_c : integer := 1;
  constant operation_response_c : integer := 2;
  
  constant cache_entry_size_c : natural := 11;
  subtype cache_line_index_t is unsigned(nsl_math.arith.log2(cache_count_c)-1 downto 0);
  subtype cache_col_index_t is unsigned(nsl_math.arith.log2(cache_entry_size_c)-1 downto 0);
  constant cache_addr_size_c : natural := cache_line_index_t'length + cache_col_index_t'length;
  subtype cache_addr_t is unsigned(cache_addr_size_c-1 downto 0);

  -- Entry layout
  constant entry_off_ttl_c : cache_col_index_t := x"0";
  constant entry_off_pa0_c : cache_col_index_t := x"1";
  constant entry_off_pa1_c : cache_col_index_t := x"2";
  constant entry_off_pa2_c : cache_col_index_t := x"3";
  constant entry_off_pa3_c : cache_col_index_t := x"4";
  constant entry_off_ha0_c : cache_col_index_t := x"5";
  constant entry_off_ha1_c : cache_col_index_t := x"6";
  constant entry_off_ha2_c : cache_col_index_t := x"7";
  constant entry_off_ha3_c : cache_col_index_t := x"8";
  constant entry_off_ha4_c : cache_col_index_t := x"9";
  constant entry_off_ha5_c : cache_col_index_t := x"a";

  -- RAM I/O
  signal lookup_ram_en_s, receiver_ram_en_s, receiver_ram_wr_s : std_ulogic;
  signal lookup_ram_addr_s, receiver_ram_addr_s : cache_addr_t;
  signal lookup_ram_rdata_s, receiver_ram_wdata_s, receiver_ram_rdata_s : byte;

  -- lookup <-> sender interface
  signal lookup_miss_s : std_ulogic;
  signal lookup_miss_pa_s : ipv4_t;
  signal sender_request_ack_s : std_ulogic;

  -- receiver <-> sender interface
  signal receiver_requested_s : std_ulogic;
  signal receiver_pa_s : ipv4_t;
  signal receiver_ha_s : mac48_t;
  signal sender_response_ack_s : std_ulogic;

  -- global ticker
  signal ticker_s: std_ulogic;
  
begin

  global: block
    constant tick_div_c: integer := clock_i_hz_c / ticker_hz_c;

    type regs_t is
    record
      tick_div: integer range 0 to tick_div_c-1;
    end record;
    
    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.tick_div <= 0;
      end if;
    end process;

    transition: process(r) is
    begin
      rin <= r;

      if r.tick_div /= 0 then
        rin.tick_div <= r.tick_div - 1;
        ticker_s <= '0';
      else
        rin.tick_div <= tick_div_c - 1;
        ticker_s <= '1';
      end if;
    end process;
  end block;
 
  lookup: block
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_QUERY_MANGLE,
      ST_PA_NEXT,
      ST_PA_LOAD3,
      ST_PA_CMP,
      ST_STALE,
      ST_MISSING,
      ST_TTL_CHECK,
      ST_HA_LOAD,
      ST_RSP,
      ST_PUT_L1,
      ST_PUT_HA,
      ST_PUT_CTX,
      ST_FAIL
      );

    constant left_max: natural := nsl_math.arith.max(6, header_i'length);

    type regs_t is
    record
      state: state_t;
      pa : ipv4_t;
      ha : mac48_t;
      ttl: byte;
      entry: cache_line_index_t;
      header: byte_string(0 to header_length_c-1);
      left: integer range 0 to left_max-1;
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

    transition: process(r, request_i, response_i, lookup_ram_rdata_s,
                        header_i, sender_request_ack_s,
                        unicast_i, netmask_i, gateway_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if request_i.valid = '1' then
            rin.pa <= shift_left(r.pa, request_i.data);
            if request_i.last = '1' then
              rin.state <= ST_QUERY_MANGLE;
            end if;
          end if;

        when ST_QUERY_MANGLE =>
          if ((r.pa xor unicast_i) and netmask_i) /= to_ipv4(0,0,0,0) then
            rin.pa <= gateway_i;
          end if;
          rin.entry <= to_unsigned(0, rin.entry'length);
          rin.state <= ST_PA_LOAD3;
          
        when ST_PA_NEXT =>
          if r.entry = cache_count_c-1 then
            rin.state <= ST_MISSING;
          else
            rin.entry <= r.entry + 1;
            rin.state <= ST_PA_LOAD3;
          end if;

        when ST_PA_LOAD3 =>
          rin.state <= ST_PA_CMP;
          rin.left <= 3;

        when ST_PA_CMP =>
          if lookup_ram_rdata_s = r.pa(r.left) then
            if r.left = 0 then
              rin.state <= ST_TTL_CHECK;
            else
              rin.left <= r.left - 1;
            end if;
          else
            rin.state <= ST_PA_NEXT;
          end if;

        when ST_TTL_CHECK =>
          rin.ttl <= lookup_ram_rdata_s;
          if lookup_ram_rdata_s(7) /= '0' then
            rin.state <= ST_STALE;
          else
            rin.state <= ST_HA_LOAD;
            rin.left <= 5;
          end if;

        when ST_HA_LOAD =>
          rin.ha <= shift_left(r.ha, lookup_ram_rdata_s);
          if r.left = 0 then
            rin.state <= ST_RSP;
          else
            rin.left <= r.left - 1;
          end if;

        when ST_STALE =>
          rin.state <= ST_MISSING;

        when ST_MISSING =>
          if sender_request_ack_s = '1' then
            rin.state <= ST_FAIL;
          end if;

        when ST_FAIL =>
          if response_i.ready = '1' then
            rin.state <= ST_IDLE;
          end if;
          
        when ST_RSP =>
          if response_i.ready = '1' then
            if header_length_c /= 0 then
              rin.left <= header_length_c-1;
              rin.state <= ST_PUT_L1;
              rin.header <= header_i;
            else
              rin.left <= 5;
              rin.state <= ST_PUT_HA;
            end if;
          end if;

        when ST_PUT_L1 =>
          if response_i.ready = '1' then
            rin.header <= shift_left(r.header);
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.left <= 5;
              rin.state <= ST_PUT_HA;
            end if;
          end if;

        when ST_PUT_HA =>
          if response_i.ready = '1' then
            rin.ha <= shift_left(r.ha);
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_PUT_CTX;
            end if;
          end if;

        when ST_PUT_CTX =>
          if response_i.ready = '1' then
            rin.state <= ST_RESET;
          end if;
      end case;
    end process;

    moore: process (r) is
      variable col: cache_col_index_t;
    begin
      col := (others => '-');
      request_o <= framed_ack_idle_c;
      response_o <= framed_req_idle_c;
      lookup_miss_s <= '0';
      lookup_miss_pa_s <= (others => (others => '-'));
      lookup_ram_en_s <= '0';

      case r.state is
        when ST_RESET =>
          null;

        when ST_IDLE =>
          request_o.ready <= '1';

        when ST_PA_NEXT | ST_QUERY_MANGLE =>
          null;

        when ST_PA_LOAD3 =>
          lookup_ram_en_s <= '1';
          col := entry_off_pa3_c;

        when ST_PA_CMP =>
          lookup_ram_en_s <= '1';
          case r.left is
            when 3 => col := entry_off_pa2_c;
            when 2 => col := entry_off_pa1_c;
            when 1 => col := entry_off_pa0_c;
            when others => col := entry_off_ttl_c;
          end case;

        when ST_TTL_CHECK =>
          lookup_ram_en_s <= '1';
          col := entry_off_ha0_c;

        when ST_HA_LOAD =>
          case r.left is
            when 5 => col := entry_off_ha1_c; lookup_ram_en_s <= '1';
            when 4 => col := entry_off_ha2_c; lookup_ram_en_s <= '1';
            when 3 => col := entry_off_ha3_c; lookup_ram_en_s <= '1';
            when 2 => col := entry_off_ha4_c; lookup_ram_en_s <= '1';
            when 1 => col := entry_off_ha5_c; lookup_ram_en_s <= '1';
            when others => null;
          end case;

        when ST_STALE =>
          lookup_ram_en_s <= '1';
          col := entry_off_ttl_c;

        when ST_MISSING =>
          lookup_miss_s <= '1';
          lookup_miss_pa_s <= r.pa;

        when ST_RSP =>
          response_o <= framed_flit(r.ttl);

        when ST_FAIL =>
          response_o <= framed_flit(x"00", last => true);

        when ST_PUT_L1 =>
          response_o <= framed_flit(first_left(r.header));

        when ST_PUT_HA =>
          response_o <= framed_flit(r.ha(0));

        when ST_PUT_CTX =>
          response_o <= framed_flit(x"00", last => true);
      end case;

      lookup_ram_addr_s <= r.entry & col;
    end process;
  end block;

  sender: block
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_PUT_HEADER,
      ST_PUT_L2_MAC,
      ST_PUT_L2_CTX,
      ST_PUT_HTYPE,
      ST_PUT_PTYPE,
      ST_PUT_HLEN,
      ST_PUT_PLEN,
      ST_PUT_OPER,
      ST_PUT_SHA,
      ST_PUT_SPA,
      ST_PUT_THA,
      ST_PUT_TPA,
      ST_COMMIT
      );
      
    constant tmp_size_c: natural := nsl_math.arith.max(header_i'length, 6);

    type regs_t is
    record
      state: state_t;
      tmp: byte_string(0 to tmp_size_c-1);
      left: integer range 0 to tmp_size_c-1;
      is_request, ack : boolean;
      pa : ipv4_t;
      ha : mac48_t;
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

    transition: process(r, lookup_miss_s, lookup_miss_pa_s, to_l2_i, hwaddr_i,
                        unicast_i, receiver_requested_s,
                        receiver_pa_s, receiver_ha_s,
                        sender_response_ack_s) is
      variable do_start : boolean;
    begin
      rin <= r;

      rin.ack <= false;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          do_start := false;
          rin.tmp <= (others => dontcare_byte_c);

          if lookup_miss_s = '1' then
            rin.is_request <= true;
            rin.ack <= true;
            rin.pa <= lookup_miss_pa_s;
            rin.ha <= ethernet_broadcast_addr_c;
            rin.tmp(0 to 5) <= ethernet_broadcast_addr_c;
            do_start := true;
          elsif receiver_requested_s = '1' then
            rin.is_request <= false;
            rin.ack <= true;
            rin.pa <= receiver_pa_s;
            rin.ha <= receiver_ha_s;
            rin.tmp(0 to 5) <= receiver_ha_s;
            do_start := true;
          end if;

          if do_start then
            if header_length_c /= 0 then
              rin.state <= ST_PUT_HEADER;
              rin.left <= header_length_c-1;
              rin.tmp(header_i'range) <= header_i;
            else
              -- tmp has been filled above
              rin.state <= ST_PUT_L2_MAC;
              rin.left <= 5;
            end if;
          end if;

        when ST_PUT_HEADER =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_PUT_L2_MAC;
              rin.tmp <= (others => dontcare_byte_c);
              rin.tmp(0 to 5) <= r.ha;
              rin.left <= 5;
            end if;
          end if;

        when ST_PUT_L2_MAC =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_PUT_L2_CTX;
            end if;
          end if;

        when ST_PUT_L2_CTX =>
          if to_l2_i.ready = '1' then
            rin.state <= ST_PUT_HTYPE;
            rin.left <= 1;
          end if;

        when ST_PUT_HTYPE =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_PUT_PTYPE;
              rin.left <= 1;
            end if;
          end if;

        when ST_PUT_PTYPE =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_PUT_HLEN;
            end if;
          end if;

        when ST_PUT_HLEN =>
          if to_l2_i.ready = '1' then
            rin.state <= ST_PUT_PLEN;
          end if;

        when ST_PUT_PLEN =>
          if to_l2_i.ready = '1' then
            rin.state <= ST_PUT_OPER;
            rin.left <= 1;
          end if;

        when ST_PUT_OPER =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_PUT_SHA;
              rin.tmp <= (others => dontcare_byte_c);
              rin.tmp(0 to 5) <= hwaddr_i;
              rin.left <= 5;
            end if;
          end if;

        when ST_PUT_SHA =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_PUT_SPA;
              rin.tmp <= (others => dontcare_byte_c);
              rin.tmp(0 to 3) <= unicast_i;
              rin.left <= 3;
            end if;
          end if;

        when ST_PUT_SPA =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_PUT_THA;
              rin.tmp <= (others => dontcare_byte_c);
              rin.tmp(0 to 5) <= r.ha;
              rin.left <= 5;
            end if;
          end if;

        when ST_PUT_THA =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_PUT_TPA;
              rin.tmp <= (others => dontcare_byte_c);
              rin.tmp(0 to 3) <= r.pa;
              rin.left <= 3;
            end if;
          end if;

        when ST_PUT_TPA =>
          if to_l2_i.ready = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
              rin.tmp <= shift_left(r.tmp);
            else
              rin.state <= ST_COMMIT;
            end if;
          end if;

        when ST_COMMIT =>
          if to_l2_i.ready = '1' then
            rin.state <= ST_RESET;
          end if;
      end case;
    end process;

    moore: process (r) is
    begin
      to_l2_o <= committed_req_idle_c;
      sender_request_ack_s <= '0';
      sender_response_ack_s <= '0';

      if r.ack then
        if r.is_request then
          sender_request_ack_s <= '1';
        else
          sender_response_ack_s <= '1';
        end if;
      end if;

      case r.state is
        when ST_RESET | ST_IDLE =>
          null;

        when ST_PUT_HEADER | ST_PUT_L2_MAC
          | ST_PUT_SHA | ST_PUT_SPA | ST_PUT_THA
          | ST_PUT_TPA =>
          to_l2_o <= committed_flit(r.tmp(0));

        when ST_PUT_L2_CTX =>
          to_l2_o <= committed_flit(x"00");

        when ST_COMMIT =>
          to_l2_o <= committed_commit(true);

        when ST_PUT_HTYPE =>
          if r.left = 1 then
            to_l2_o <= committed_flit(x"00");
          else
            to_l2_o <= committed_flit(x"01");
          end if;
          
        when ST_PUT_PTYPE =>
          if r.left = 1 then
            to_l2_o <= committed_flit(x"08");
          else
            to_l2_o <= committed_flit(x"00");
          end if;
          
        when ST_PUT_HLEN =>
          to_l2_o <= committed_flit(x"06");
          
        when ST_PUT_PLEN =>
          to_l2_o <= committed_flit(x"04");

        when ST_PUT_OPER =>
          if r.left = 1 then
            to_l2_o <= committed_flit(x"00");
          elsif r.is_request then
            to_l2_o <= committed_flit(to_byte(operation_request_c));
          else
            to_l2_o <= committed_flit(to_byte(operation_response_c));
          end if;
      end case;
    end process;
  end block;

  receiver: block
    type state_t is (
      ST_INIT,
      ST_INIT_TTL_WRITE,
      ST_IDLE,
      ST_GET_L1,
      ST_GET_L2,
      ST_GET_HTYPE,
      ST_GET_PTYPE,
      ST_GET_HLEN,
      ST_GET_PLEN,
      ST_GET_OPER,
      ST_GET_SHA,
      ST_GET_SPA,
      ST_GET_THA,
      ST_GET_TPA,
      ST_GET_COMMIT,
      ST_DROP,
      ST_REQ_HANDLE,
      ST_VICTIM_TTL_LOAD,
      ST_VICTIM_TTL_CMP,
      ST_VICTIM_PA_CMP,
      ST_VICTIM_PA_WRITE,
      ST_VICTIM_HA_WRITE,
      ST_VICTIM_TTL_WRITE,
      ST_DECAY_TTL_LOAD,
      ST_DECAY_TTL_DEC,
      ST_DECAY_TTL_STORE,
      ST_NOTIFY_PA_LOAD,
      ST_NOTIFY_PA_CMP,
      ST_NOTIFY_HA_CMP,
      ST_NOTIFY_TTL_READ,
      ST_NOTIFY_TTL_WRITE
      );

    constant tmp_size_c: natural := nsl_math.arith.max(header_i'length, ethernet_layer_header_length_c);

    type regs_t is
    record
      state: state_t;
      left : integer range 0 to tmp_size_c-1;
      ha: mac48_t;
      pa, ref_pa: ipv4_t;
      is_request: boolean;
      default_entry, entry: cache_line_index_t;
      decay_pending: boolean;
      ttl: unsigned(7 downto 0);

      notify_pending: boolean;
      notify_pa: ipv4_t;
      notify_ha: mac48_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;
      if reset_n_i = '0' then
        r.state <= ST_INIT;
      end if;
    end process;

    transition: process(r, from_l2_i, unicast_i, sender_response_ack_s, ticker_s,
                        receiver_ram_rdata_s, notify_i, notify_valid_i) is
    begin
      rin <= r;

      -- Catch all. Handle specially in GET_COMMIT
      if from_l2_i.valid = '1' and from_l2_i.last = '1' then
        rin.state <= ST_IDLE;
      end if;

      if ticker_s = '1' then
        rin.decay_pending <= true;
      end if;

      if notify_valid_i = '1' and not r.notify_pending then
        if notify_i(header_length_c+6) = x"00" and
          notify_i(header_length_c+6+1+4) = x"00" then
          rin.notify_ha <= notify_i(header_length_c to header_length_c+5);
          rin.notify_pa <= notify_i(header_length_c+6+1 to header_length_c+6+4);
          rin.notify_pending <= true;
        end if;
      end if;
      
      case r.state is
        when ST_INIT =>
          rin.state <= ST_INIT_TTL_WRITE;
          rin.entry <= (others => '0');
          rin.ttl <= x"ff";

        when ST_INIT_TTL_WRITE =>
          if r.entry /= cache_count_c - 1 then
            rin.entry <= r.entry + 1;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_IDLE =>
          rin.ref_pa <= unicast_i;

          if from_l2_i.valid = '1' then
            if header_length_c /= 0 then
              rin.left <= header_length_c-1;
              rin.state <= ST_GET_L1;
            else
              rin.left <= ethernet_layer_header_length_c-1;
              rin.state <= ST_GET_L2;
            end if;
          elsif r.decay_pending then
            rin.decay_pending <= false;
            rin.entry <= (others => '0');
            rin.state <= ST_DECAY_TTL_LOAD;
          elsif r.notify_pending then
            rin.entry <= (others => '0');
            rin.state <= ST_NOTIFY_PA_LOAD;
          end if;

        when ST_GET_L1 =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.left <= ethernet_layer_header_length_c-1;
              rin.state <= ST_GET_L2;
            end if;
          end if;

        when ST_GET_L2 =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.left <= 1;
              rin.state <= ST_GET_HTYPE;
            end if;
          end if;

        when ST_GET_HTYPE =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.left <= 1;
              rin.state <= ST_GET_PTYPE;
            end if;

            if (r.left = 1 and from_l2_i.data /= x"00")
              or (r.left = 0 and from_l2_i.data /= x"01") then
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_GET_PTYPE =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_HLEN;
            end if;

            if (r.left = 1 and from_l2_i.data /= x"08")
              or (r.left = 0 and from_l2_i.data /= x"00") then
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_GET_HLEN =>
          if from_l2_i.valid = '1' then
            rin.state <= ST_GET_PLEN;

            if from_l2_i.data /= x"06" then
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_GET_PLEN =>
          if from_l2_i.valid = '1' then
            rin.state <= ST_GET_OPER;
            rin.left <= 1;

            if from_l2_i.data /= x"04" then
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_GET_OPER =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_SHA;
              rin.left <= 5;
            end if;

            rin.is_request
              <= r.left = 0
              and from_l2_i.data = to_byte(operation_request_c);
            
            if (r.left = 1 and from_l2_i.data /= x"00")
              or (r.left = 0
                  and from_l2_i.data /= to_byte(operation_response_c)
                  and from_l2_i.data /= to_byte(operation_request_c)) then
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_GET_SHA =>
          if from_l2_i.valid = '1' then
            rin.ha <= shift_left(r.ha, from_l2_i.data);
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_SPA;
              rin.left <= 3;
            end if;
          end if;

        when ST_GET_SPA =>
          if from_l2_i.valid = '1' then
            rin.pa <= shift_left(r.pa, from_l2_i.data);
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_THA;
              rin.left <= 5;
            end if;
          end if;

        when ST_GET_THA =>
          if from_l2_i.valid = '1' then
            if r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_TPA;
              rin.left <= 3;
            end if;
          end if;

        when ST_GET_TPA =>
          if from_l2_i.valid = '1' then
            rin.ref_pa <= shift_left(r.ref_pa);
            if r.ref_pa(0) /= from_l2_i.data then
              rin.state <= ST_DROP;
            elsif r.left /= 0 then
              rin.left <= r.left - 1;
            else
              rin.state <= ST_GET_COMMIT;
            end if;
          end if;

        when ST_GET_COMMIT =>
          if from_l2_i.valid = '1' and from_l2_i.last = '1' then
            if from_l2_i.data = x"00" then
              rin.state <= ST_IDLE;
            elsif r.is_request then
              rin.state <= ST_REQ_HANDLE;
            else
              rin.state <= ST_VICTIM_TTL_LOAD;
              rin.entry <= to_unsigned(0, rin.entry'length);
              rin.default_entry <= to_unsigned(0, rin.entry'length);
            end if;
          end if;  

        when ST_DROP =>
          if from_l2_i.valid = '1' and from_l2_i.last = '1' then
            rin.state <= ST_IDLE;
          end if;  

        when ST_VICTIM_TTL_LOAD =>
          rin.state <= ST_VICTIM_TTL_CMP;
          
        when ST_VICTIM_TTL_CMP =>
          rin.left <= 3;
          rin.state <= ST_VICTIM_PA_CMP;
          rin.ref_pa <= r.pa;
          -- Any expired entry can be used as default
          if receiver_ram_rdata_s(7) = '1' then
            rin.default_entry <= r.entry;
          end if;

        when ST_VICTIM_PA_CMP =>
          rin.ref_pa <= shift_left(r.ref_pa);
          if r.left /= 0 then
            rin.left <= r.left - 1;
          end if;

          if receiver_ram_rdata_s /= r.ref_pa(0) then
            -- PA is not matching...
            if r.entry /= cache_count_c-1 then
              -- ... short cut to next entry comparison ...
              rin.entry <= r.entry + 1;
              rin.state <= ST_VICTIM_TTL_LOAD;
            else
              -- ... or write PA to default entry
              rin.state <= ST_VICTIM_PA_WRITE;
              rin.entry <= r.default_entry;
              rin.left <= 3;
            end if;
          elsif r.left = 0 then
            -- We touched an expired entry that has matching PA, take
            -- it straight to write new HA
            rin.state <= ST_VICTIM_HA_WRITE;
            rin.left <= 5;
          end if;

        when ST_VICTIM_PA_WRITE =>
          rin.pa <= shift_left(r.pa);
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_VICTIM_HA_WRITE;
            rin.left <= 5;
          end if;

        when ST_VICTIM_HA_WRITE =>
          rin.ha <= shift_left(r.ha);
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_VICTIM_TTL_WRITE;
            rin.ttl <= to_unsigned(ttl_init_value_c, 8);
          end if;

        when ST_VICTIM_TTL_WRITE =>
          rin.state <= ST_IDLE;
          
        when ST_REQ_HANDLE =>
          if sender_response_ack_s = '1' then
            rin.state <= ST_IDLE;
          end if;

        when ST_DECAY_TTL_LOAD =>
          rin.state <= ST_DECAY_TTL_DEC;

        when ST_DECAY_TTL_DEC =>
          if receiver_ram_rdata_s(7) /= '1' then
            rin.state <= ST_DECAY_TTL_STORE;
            rin.ttl <= unsigned(receiver_ram_rdata_s) - 1;
          elsif r.entry /= cache_count_c - 1 then
            rin.entry <= r.entry + 1;
            rin.state <= ST_DECAY_TTL_LOAD;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_DECAY_TTL_STORE =>
          if r.entry /= cache_count_c - 1 then
            rin.entry <= r.entry + 1;
            rin.state <= ST_DECAY_TTL_LOAD;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_NOTIFY_PA_LOAD =>
          rin.state <= ST_NOTIFY_PA_CMP;
          rin.ref_pa <= r.notify_pa;
          rin.left <= 3;

        when ST_NOTIFY_PA_CMP =>
          rin.ref_pa <= shift_left(r.ref_pa);
          if r.left /= 0 then
            rin.left <= r.left - 1;
          end if;

          if receiver_ram_rdata_s /= r.ref_pa(0) then
            if r.entry /= cache_count_c-1 then
              rin.entry <= r.entry + 1;
              rin.state <= ST_NOTIFY_PA_LOAD;
            else
              rin.notify_pending <= false;
              rin.state <= ST_IDLE;
            end if;
          elsif r.left = 0 then
            rin.state <= ST_NOTIFY_HA_CMP;
            rin.left <= 5;
            rin.ha <= r.notify_ha;
          end if;

        when ST_NOTIFY_HA_CMP =>
          rin.ha <= shift_left(r.ha);
          if r.left /= 0 then
            rin.left <= r.left - 1;
          end if;

          if receiver_ram_rdata_s /= r.ha(0) then
            if r.entry /= cache_count_c-1 then
              rin.entry <= r.entry + 1;
              rin.state <= ST_NOTIFY_PA_LOAD;
            else
              rin.notify_pending <= false;
              rin.state <= ST_IDLE;
            end if;
          elsif r.left = 0 then
            rin.state <= ST_NOTIFY_TTL_READ;
            rin.left <= 5;
          end if;

        when ST_NOTIFY_TTL_READ =>
          rin.ttl <= to_unsigned(ttl_init_value_c, 8);
          if receiver_ram_rdata_s(7) /= '1' then
            rin.state <= ST_NOTIFY_TTL_WRITE;
          else
            rin.notify_pending <= false;
            rin.state <= ST_IDLE;
          end if;

        when ST_NOTIFY_TTL_WRITE =>
          rin.notify_pending <= false;
          rin.state <= ST_IDLE;
          
      end case;
    end process;

    moore: process (r) is
      variable col: cache_col_index_t;
    begin
      col := (others => '-');
      from_l2_o.ready <= '0';
      receiver_ram_en_s <= '0';
      receiver_ram_wr_s <= '0';
      receiver_ram_wdata_s <= (others => '-');
      receiver_ha_s <= r.ha;
      receiver_pa_s <= r.pa;
      receiver_requested_s <= '0';

      case r.state is
        when ST_INIT | ST_IDLE | ST_DECAY_TTL_DEC =>
          null;

        when ST_REQ_HANDLE =>
          receiver_requested_s <= '1';

        when ST_GET_L1 | ST_GET_L2
          | ST_GET_HTYPE | ST_GET_PTYPE | ST_GET_HLEN | ST_GET_PLEN
          | ST_GET_OPER | ST_GET_SHA | ST_GET_SPA | ST_GET_THA | ST_GET_TPA
          | ST_GET_COMMIT | ST_DROP =>
          from_l2_o.ready <= '1';

        when ST_VICTIM_TTL_LOAD | ST_DECAY_TTL_LOAD =>
          col := entry_off_ttl_c; receiver_ram_en_s <= '1';

        when ST_VICTIM_TTL_CMP =>
          col := entry_off_pa0_c; receiver_ram_en_s <= '1';

        when ST_VICTIM_PA_CMP =>
          case r.left is
            when 3 => col := entry_off_pa1_c; receiver_ram_en_s <= '1';
            when 2 => col := entry_off_pa2_c; receiver_ram_en_s <= '1';
            when 1 => col := entry_off_pa3_c; receiver_ram_en_s <= '1';
            when others => null;
          end case;

        when ST_VICTIM_HA_WRITE =>
          receiver_ram_en_s <= '1';
          receiver_ram_wr_s <= '1';
          receiver_ram_wdata_s <= r.ha(0);
          col := entry_off_ha5_c - r.left;

        when ST_VICTIM_PA_WRITE =>
          receiver_ram_en_s <= '1';
          receiver_ram_wr_s <= '1';
          receiver_ram_wdata_s <= r.pa(0);
          col := entry_off_pa3_c - r.left;

        when ST_VICTIM_TTL_WRITE | ST_DECAY_TTL_STORE | ST_INIT_TTL_WRITE
          | ST_NOTIFY_TTL_WRITE =>
          receiver_ram_en_s <= '1';
          receiver_ram_wr_s <= '1';
          receiver_ram_wdata_s <= std_ulogic_vector(r.ttl);
          col := entry_off_ttl_c;

        when ST_NOTIFY_PA_LOAD =>
          col := entry_off_pa0_c; receiver_ram_en_s <= '1';

        when ST_NOTIFY_PA_CMP =>
          case r.left is
            when 3 => col := entry_off_pa1_c; receiver_ram_en_s <= '1';
            when 2 => col := entry_off_pa2_c; receiver_ram_en_s <= '1';
            when 1 => col := entry_off_pa3_c; receiver_ram_en_s <= '1';
            when others => col := entry_off_ha0_c; receiver_ram_en_s <= '1';
          end case;

        when ST_NOTIFY_HA_CMP =>
          case r.left is
            when 5 => col := entry_off_ha1_c; receiver_ram_en_s <= '1';
            when 4 => col := entry_off_ha2_c; receiver_ram_en_s <= '1';
            when 3 => col := entry_off_ha3_c; receiver_ram_en_s <= '1';
            when 2 => col := entry_off_ha4_c; receiver_ram_en_s <= '1';
            when 1 => col := entry_off_ha5_c; receiver_ram_en_s <= '1';
            when others => col := entry_off_ttl_c; receiver_ram_en_s <= '1';
          end case;

        when ST_NOTIFY_TTL_READ =>
          null;

      end case;

      receiver_ram_addr_s <= r.entry & col;
    end process;
  end block;
  
  storage: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => cache_addr_size_c,
      word_size_c => 8,
      data_word_count_c => 1,
      registered_output_c => false,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i,

      a_enable_i => receiver_ram_en_s,
      a_write_en_i(0) => receiver_ram_wr_s,
      a_address_i => receiver_ram_addr_s,
      a_data_i => receiver_ram_wdata_s,
      a_data_o => receiver_ram_rdata_s,

      b_clock_i => clock_i,

      b_enable_i => lookup_ram_en_s,
      b_address_i => lookup_ram_addr_s,
      b_data_o => lookup_ram_rdata_s
      );
      
end architecture;
