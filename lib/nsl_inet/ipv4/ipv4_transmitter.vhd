library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ipv4.all;
use nsl_logic.bool.all;

entity ipv4_transmitter is
  generic(
    ttl_c : integer := 64;
    header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    unicast_i : in ipv4_t;

    l4_i : in committed_req;
    l4_o : out committed_ack;

    l2_o : out committed_req;
    l2_i : in committed_ack
    );
end entity;

architecture beh of ipv4_transmitter is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_PEER_IP,
    IN_CTX,
    IN_PROTO,
    IN_PDU_LEN,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER,
    OUT_VER_LEN,
    OUT_TOS,
    OUT_LEN_WAIT,
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
  constant max_step_c : integer := nsl_math.arith.max(header_length_c, 4);

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    src_addr, dst_addr : ipv4_t;
    total_len : unsigned(15 downto 0);
    proto : byte;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_state : out_state_t;
    out_left : integer range 0 to max_step_c-1;
  end record;

  signal r, rin: regs_t;
  
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

  transition: process(r, l2_i, l4_i, unicast_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_HEADER;
        rin.in_left <= header_length_c - 1;

      when IN_HEADER =>
        rin.src_addr <= unicast_i;

        if l4_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;

          if r.in_left = 0 then
            rin.in_state <= IN_PEER_IP;
            rin.in_left <= 3;
          else
            rin.in_left <= r.in_left - 1;
          end if;
        end if;

      when IN_PEER_IP =>
        if l4_i.valid = '1' then
          if l4_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.dst_addr <= r.dst_addr(1 to 3) & l4_i.data;
            rin.src_addr <= r.src_addr(1 to 3) & r.src_addr(0);
            
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_CTX;
            end if;
          end if;
        end if;

      when IN_CTX =>
        if l4_i.valid = '1' then
          if l4_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.in_state <= IN_PROTO;
          end if;
        end if;

      when IN_PROTO =>
        if l4_i.valid = '1' then
          rin.proto <= l4_i.data;
          if l4_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.in_state <= IN_PDU_LEN;
            rin.in_left <= 1;
          end if;
        end if;

      when IN_PDU_LEN =>
        if l4_i.valid = '1' then
          if l4_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.total_len <= r.total_len(7 downto 0) & unsigned(l4_i.data);
            if r.in_left = 0 then
              rin.in_state <= IN_DATA;
            else
              rin.in_left <= r.in_left - 1;
            end if;
          end if;
        end if;

      when IN_DATA =>
        if l4_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if l4_i.last = '0' then
            fifo_push := true;
          elsif l4_i.data = x"01" then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        if header_length_c /= 0 and r.in_state = IN_HEADER then
          rin.out_state <= OUT_HEADER;
          rin.out_left <= header_length_c - 1;
        end if;
        if header_length_c = 0 and r.in_state = IN_PEER_IP then
          rin.out_state <= OUT_VER_LEN;
        end if;

      when OUT_HEADER =>
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
          rin.out_state <= OUT_TOS;
        end if;

      when OUT_TOS =>
        if l2_i.ready = '1' then
          rin.out_state <= OUT_LEN_WAIT;
        end if;

      when OUT_LEN_WAIT =>
        if r.in_state = IN_DATA or r.in_state = IN_COMMIT then
          rin.total_len <= r.total_len + 20;
          rin.out_state <= OUT_TOTAL_LEN;
          rin.out_left <= 1;
        end if;
        if r.in_state = IN_CANCEL then
          rin.out_state <= OUT_CANCEL;
        end if;

      when OUT_TOTAL_LEN =>
        if l2_i.ready = '1' then
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
          if r.out_left = 0 then
            rin.out_state <= OUT_FRAG_OFF;
            rin.out_left <= 1;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_FRAG_OFF =>
        if l2_i.ready = '1' then
          if r.out_left = 0 then
            rin.out_state <= OUT_TTL;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_TTL =>
        if l2_i.ready = '1' then
          rin.out_state <= OUT_PROTO;
        end if;

      when OUT_PROTO =>
        if l2_i.ready = '1' then
          rin.out_state <= OUT_CHKSUM;
          rin.out_left <= 1;
        end if;

      when OUT_CHKSUM =>
        if l2_i.ready = '1' then
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
      rin.fifo(r.fifo_fillness-1) <= l4_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= l4_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.in_state is
      when IN_RESET | IN_COMMIT | IN_CANCEL =>
        l4_o <= committed_ack_idle_c;
        
      when IN_PEER_IP | IN_CTX | IN_PROTO | IN_PDU_LEN =>
        l4_o <= committed_accept(true);

      when IN_HEADER | IN_DATA =>
        l4_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET | OUT_LEN_WAIT =>
        l2_o <= committed_req_idle_c;

      when OUT_HEADER | OUT_DATA =>
        l2_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_VER_LEN =>
        l2_o <= committed_flit(x"45");
        
      when OUT_TOS | OUT_IDENTIFICATION | OUT_FRAG_OFF | OUT_CHKSUM =>
        l2_o <= committed_flit(x"00");

      when OUT_TOTAL_LEN =>
        l2_o <= committed_flit(std_ulogic_vector(r.total_len(15 downto 8)));

      when OUT_TTL =>
        l2_o <= committed_flit(to_byte(ttl_c));

      when OUT_PROTO =>
        l2_o <= committed_flit(r.proto);

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
  
end architecture;
