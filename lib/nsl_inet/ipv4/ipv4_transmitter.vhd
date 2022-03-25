library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;
use nsl_logic.bool.all;

entity ipv4_transmitter is
  generic(
    ttl_c : integer := 64;
    mtu_c : integer := 1500;
    l12_header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    unicast_i : in ipv4_t;

    l4_i : in committed_req;
    l4_o : out committed_ack;

    l2_o : out committed_req;
    l2_i : in committed_ack;

    l12_query_o : out framed_req;
    l12_query_i : in framed_ack;
    l12_reply_i : in framed_req;
    l12_reply_o : out framed_ack
    );
end entity;

architecture beh of ipv4_transmitter is

  type in_state_t is (
    IN_RESET,
    IN_SIZE,
    IN_PROTO,
    IN_PEER_IP,
    IN_CTX,
    IN_RESOLVE_CMD,
    IN_RESOLVE_RSP,
    IN_L12_HEADER,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL,
    IN_DROP
    );

  type out_state_t is (
    OUT_RESET,
    OUT_L12_HEADER,
    OUT_VER_LEN,
    OUT_TOS,
    OUT_TOTAL_LEN,
    OUT_IDENTIFICATION,
    OUT_FRAG_OFF,
    OUT_TTL,
    OUT_PROTO,
    OUT_CHKSUM,
    OUT_SRC_ADDR,
    OUT_DST_ADDR,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;
  constant max_step_c : integer := nsl_math.arith.max(l12_header_length_c, 4);

  signal l4_s: committed_bus;
  signal total_size_s: unsigned(nsl_math.arith.log2(mtu_c)-1 downto 0);
  signal total_size_ready_s, total_size_valid_s: std_ulogic;

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    src_addr, dst_addr : ipv4_t;
    total_len : unsigned(15 downto 0);
    checksum : checksum_t;
    proto : byte;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_state : out_state_t;
    out_left : integer range 0 to max_step_c-1;
  end record;

  signal r, rin: regs_t;

  -- Header checksum:
  -- 45 | TOS      == cst | 0
  -- Len           == var
  -- Id            == 0
  -- Off           == 0
  -- TTL | Proto   == cst | var
  -- Chk           -> dest
  -- src(0 to 1)   == var
  -- src(2 to 3)   == var
  -- dst(0 to 1)   == var
  -- dst(2 to 3)   == var
  -- src/dst IP are transmitter after checksum, we need to sum them up before.
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
    end if;
  end process;

  transition: process(r, l2_i, l4_s.req, unicast_i,
                      l12_query_i, l12_reply_i,
                      total_size_valid_s, total_size_s) is
    variable fifo_push, fifo_pop: boolean;
    variable fifo_data : byte;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    fifo_data := "--------";

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_SIZE;

      when IN_SIZE =>
        if total_size_valid_s = '1' then
          rin.total_len <= resize(total_size_s, 16);
          rin.in_state <= IN_PROTO;
        end if;

        when IN_PROTO =>
        if l4_s.req.valid = '1' then
          rin.proto <= l4_s.req.data;
          if l4_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.in_state <= IN_PEER_IP;
            rin.in_left <= 3;
            rin.src_addr <= unicast_i;
            rin.checksum <= (others => '0');
          end if;
        end if;

      when IN_PEER_IP =>
        if l4_s.req.valid = '1' then
          if l4_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.dst_addr <= r.dst_addr(1 to 3) & l4_s.req.data;
            rin.src_addr <= r.src_addr(1 to 3) & r.src_addr(0);
            if r.in_left = 3 or r.in_left = 1 then
              rin.checksum <= checksum_update(r.checksum,
                                              byte_string'(0 => l4_s.req.data,
                                                           1 => r.src_addr(1)));
            else
              rin.checksum <= checksum_update(r.checksum,
                                              byte_string'(0 => r.src_addr(1),
                                                           1 => l4_s.req.data));
            end if;
            
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_CTX;
            end if;
          end if;
        end if;

      when IN_CTX =>
        if l4_s.req.valid = '1' then
          if l4_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            if l12_header_length_c /= 0 then
              rin.in_state <= IN_RESOLVE_CMD;
              rin.in_left <= 3;
            else
              rin.in_state <= IN_DATA;
            end if;
          end if;
        end if;

      when IN_RESOLVE_CMD =>
        if l12_query_i.ready = '1' then
          rin.dst_addr <= r.dst_addr(1 to 3) & r.dst_addr(0);
          if r.in_left = 0 then
            rin.in_state <= IN_RESOLVE_RSP;
          else
            rin.in_left <= r.in_left - 1;
          end if;
        end if;

      when IN_RESOLVE_RSP =>
        if l12_reply_i.valid = '1' then
          if l12_reply_i.last = '1' then
            rin.in_state <= IN_DROP;
          else
            rin.in_state <= IN_L12_HEADER;
            rin.in_left <= l12_header_length_c - 1;
          end if;
        end if;

      when IN_L12_HEADER =>
        if l12_reply_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          fifo_data := l12_reply_i.data;

          if r.in_left = 0 then
            rin.in_state <= IN_DATA;
          else
            rin.in_left <= r.in_left - 1;
          end if;
        end if;

      when IN_DATA =>
        if l4_s.req.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if l4_s.req.last = '0' then
            fifo_push := true;
            fifo_data := l4_s.req.data;
          elsif l4_s.req.data = x"01" then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
          rin.in_state <= IN_RESET;
        end if;

      when IN_DROP =>
        if l4_s.req.valid = '1' and l4_s.req.last = '1' then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        if l12_header_length_c /= 0 and r.in_state = IN_L12_HEADER then
          rin.out_state <= OUT_L12_HEADER;
          rin.out_left <= l12_header_length_c - 1;
        end if;
        if l12_header_length_c = 0 and r.in_state = IN_DATA then
          rin.out_state <= OUT_VER_LEN;
        end if;

      when OUT_L12_HEADER =>
        if r.fifo_fillness /= 0 and l2_i.ready = '1' then
          fifo_pop := true;
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_VER_LEN;
          end if;
        end if;

      when OUT_VER_LEN =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, x"45");
          rin.out_state <= OUT_TOS;
        end if;

      when OUT_TOS =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, x"00");
          rin.out_state <= OUT_TOTAL_LEN;
          rin.out_left <= 1;
        end if;

      when OUT_TOTAL_LEN =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum,
                                          std_ulogic_vector(r.total_len(15 downto 8)));
          rin.total_len <= r.total_len(7 downto 0) & r.total_len(15 downto 8);
          if r.out_left = 0 then
            rin.out_state <= OUT_IDENTIFICATION;
            rin.out_left <= 1;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_IDENTIFICATION =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, x"00");
          if r.out_left = 0 then
            rin.out_state <= OUT_FRAG_OFF;
            rin.out_left <= 1;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_FRAG_OFF =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, x"00");
          if r.out_left = 0 then
            rin.out_state <= OUT_TTL;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_TTL =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, to_byte(ttl_c));
          rin.out_state <= OUT_PROTO;
        end if;

      when OUT_PROTO =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, r.proto);
          rin.out_state <= OUT_CHKSUM;
          rin.out_left <= 1;
        end if;

      when OUT_CHKSUM =>
        if l2_i.ready = '1' then
          rin.checksum <= checksum_update(r.checksum, x"00");
          if r.out_left = 0 then
            rin.out_state <= OUT_SRC_ADDR;
            rin.out_left <= 3;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_SRC_ADDR =>
        if l2_i.ready = '1' then
          rin.src_addr <= r.src_addr(1 to 3) & r.src_addr(0);
          if r.out_left = 0 then
            rin.out_state <= OUT_DST_ADDR;
            rin.out_left <= 3;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_DST_ADDR =>
        if l2_i.ready = '1' then
          rin.dst_addr <= r.dst_addr(1 to 3) & r.dst_addr(0);
          if r.out_left = 0 then
            rin.out_state <= OUT_DATA;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_DATA =>
        if l2_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (l2_i.ready = '1' and r.fifo_fillness = 1) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          elsif r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if l2_i.ready = '1' then
          rin.out_state <= OUT_RESET;
        end if;

    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= fifo_data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= fifo_data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    l2_o <= committed_req_idle_c;
    l4_s.ack <= committed_ack_idle_c;
    l12_query_o <= framed_req_idle_c;
    l12_reply_o <= framed_ack_idle_c;
    total_size_ready_s <= '0';

    case r.in_state is
      when IN_RESET =>
        null;

      when IN_SIZE =>
        total_size_ready_s <= '1';
        
      when IN_PEER_IP | IN_CTX | IN_DROP | IN_PROTO =>
        l4_s.ack <= committed_accept(true);

      when IN_RESOLVE_CMD =>
        l12_query_o <= framed_flit(r.dst_addr(0), last => r.in_left = 0);
        
      when IN_RESOLVE_RSP =>
        l12_reply_o <= framed_accept(true);

      when IN_L12_HEADER =>
        l12_reply_o <= framed_accept(r.fifo_fillness < fifo_depth_c);

      when IN_DATA =>
        l4_s.ack <= committed_accept(r.fifo_fillness < fifo_depth_c);

      when IN_COMMIT | IN_CANCEL =>
    end case;

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_L12_HEADER | OUT_DATA =>
        l2_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_VER_LEN =>
        l2_o <= committed_flit(x"45");
        
      when OUT_TOS | OUT_IDENTIFICATION | OUT_FRAG_OFF =>
        l2_o <= committed_flit(x"00");

      when OUT_TOTAL_LEN =>
        l2_o <= committed_flit(std_ulogic_vector(r.total_len(15 downto 8)));

      when OUT_TTL =>
        l2_o <= committed_flit(to_byte(ttl_c));

      when OUT_PROTO =>
        l2_o <= committed_flit(r.proto);

      when OUT_CHKSUM =>
        l2_o <= committed_flit(not std_ulogic_vector(r.checksum(15 downto 8)));

      when OUT_SRC_ADDR =>
        l2_o <= committed_flit(r.src_addr(0));

      when OUT_DST_ADDR =>
        l2_o <= committed_flit(r.dst_addr(0));

      when OUT_COMMIT =>
        l2_o <= committed_commit(true);

      when OUT_CANCEL =>
        l2_o <= committed_commit(false);
    end case;
  end process;

  sizer: nsl_bnoc.committed.committed_sizer
    generic map(
      clock_count_c => 1,
      -- Size of IP header minus l4 header (proto + daddr + ctx)
      offset_c => 20 - 6,
      txn_count_c => 4,
      max_size_l2_c => total_size_s'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_i => l4_i,
      in_o => l4_o,

      out_o => l4_s.req,
      out_i => l4_s.ack,

      size_o => total_size_s,
      size_valid_o => total_size_valid_s,
      size_ready_i => total_size_ready_s
      );
  
end architecture;
