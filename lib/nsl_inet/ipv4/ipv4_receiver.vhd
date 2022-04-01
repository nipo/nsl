library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math, nsl_logic;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;
use nsl_logic.bool.all;

entity ipv4_receiver is
  generic(
    header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    unicast_i : in ipv4_t;
    broadcast_i : in ipv4_t;

    l2_i : in nsl_bnoc.committed.committed_req;
    l2_o : out nsl_bnoc.committed.committed_ack;

    l4_o : out nsl_bnoc.committed.committed_req;
    l4_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of ipv4_receiver is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_VER_LEN,
    IN_TOS,
    IN_TOTAL_LEN,
    IN_IDENTIFICATION,
    IN_FRAG_OFF,
    IN_TTL,
    IN_PROTO,
    IN_CHKSUM,
    IN_SRC_ADDR,
    IN_DST_ADDR,
    IN_OPTS,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL,
    IN_DROP
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER_PEER_IP,
    OUT_CTX_WAIT,
    OUT_CTX,
    OUT_PROTO,
    OUT_LEN,
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

    unicast_addr, bcast_addr : ipv4_t;
    is_bcast, is_unicast: boolean;
    -- Use this counter MSB as an enable. When counter wraps, we are
    -- in padding. Still read input, but dont push to fifo
    pdu_len, total_len : unsigned(15 downto 0);
    header_chk : checksum_t;
    header_left : unsigned(5 downto 0);
    proto : byte;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    
    out_state : out_state_t;
    out_left : integer range 0 to max_step_c+4-1;
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

  transition: process(r, l2_i, l4_i, unicast_i, broadcast_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.header_chk <= (others => '0');
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c - 1;
        else
          rin.in_state <= IN_VER_LEN;
        end if;

      when IN_HEADER =>
        if l2_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          elsif r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
          else
            rin.in_state <= IN_VER_LEN;
          end if;
        end if;

      when IN_VER_LEN =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          elsif l2_i.data(7 downto 4) /= x"4" then
            rin.in_state <= IN_DROP;
          elsif unsigned(l2_i.data(3 downto 0)) < 5 then
            rin.in_state <= IN_DROP;
          else
            rin.header_left <= (unsigned(l2_i.data(3 downto 0)) - 1) & "10";
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);

            rin.in_state <= IN_TOS;
          end if;
        end if;
        
      when IN_TOS =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);

            rin.in_state <= IN_TOTAL_LEN;
            rin.in_left <= 1;
          end if;
        end if;

      when IN_TOTAL_LEN =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);

            rin.total_len <= r.total_len(7 downto 0) & unsigned(l2_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 1;
              rin.in_state <= IN_IDENTIFICATION;
            end if;
          end if;
        end if;

      when IN_IDENTIFICATION =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);

            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.total_len <= r.total_len - 7;
              rin.in_left <= 1;
              rin.in_state <= IN_FRAG_OFF;
            end if;
          end if;
        end if;

      when IN_FRAG_OFF =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            if l2_i.data /= x"00" and r.in_left = 0 then
              rin.in_state <= IN_DROP;
            elsif l2_i.data(5 downto 0) /= "000000" and r.in_left = 1 then
              rin.in_state <= IN_DROP;
            elsif r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_TTL;
            end if;
          end if;
        end if;

      when IN_TTL =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            rin.in_state <= IN_PROTO;
          end if;
        end if;

      when IN_PROTO =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            rin.proto <= l2_i.data;
            rin.in_state <= IN_CHKSUM;
            rin.in_left <= 1;
          end if;
        end if;

      when IN_CHKSUM =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 3;
              rin.in_state <= IN_SRC_ADDR;
            end if;
          end if;
        end if;

      when IN_SRC_ADDR =>
        rin.unicast_addr <= unicast_i;
        rin.bcast_addr <= broadcast_i;
        rin.is_bcast <= true;
        rin.is_unicast <= true;

        if l2_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;

          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;
            
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 3;
              rin.in_state <= IN_DST_ADDR;
            end if;
          end if;
        end if;

      when IN_DST_ADDR =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            rin.is_bcast <= r.is_bcast and l2_i.data = r.bcast_addr(0);
            rin.is_unicast <= r.is_unicast and l2_i.data = r.unicast_addr(0);

            rin.unicast_addr <= shift_left(r.unicast_addr);
            rin.bcast_addr <= shift_left(r.bcast_addr);

            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            elsif r.header_left = 0 then
              rin.pdu_len <= r.total_len;
              rin.in_state <= IN_DATA;
            else
              rin.in_state <= IN_OPTS;
            end if;
          end if;
        end if;

      when IN_OPTS =>
        if l2_i.valid = '1' then
          if l2_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            rin.header_left <= r.header_left - 1;
            rin.header_chk <= checksum_update(r.header_chk, l2_i.data);
            rin.total_len <= r.total_len - 1;

            if r.header_left = 0 then
              rin.pdu_len <= r.total_len;
              rin.in_state <= IN_DATA;
            end if;
          end if;
        end if;

      when IN_DATA =>
        if l2_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          rin.header_chk <= checksum_update(r.header_chk, x"00");

          if l2_i.last = '0' then
            if r.total_len(15) = '0' then
              rin.total_len <= r.total_len - 1;
              fifo_push := true;
            end if;
          elsif l2_i.data = x"01" and r.header_chk = "01111111111111111"
            and (r.is_unicast or r.is_bcast)
            and (r.total_len(15) = '1') then
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
        if l2_i.valid = '1' and l2_i.last = '1' then
          rin.in_state <= IN_RESET;
        end if;
          
    end case;
    
    case r.out_state is
      when OUT_RESET =>
        if r.in_state = IN_HEADER then
          rin.out_state <= OUT_HEADER_PEER_IP;
          rin.out_left <= header_length_c + 4 - 1;
        end if;

      when OUT_HEADER_PEER_IP =>
        if l4_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;

          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          elsif r.in_state = IN_DST_ADDR then
            rin.out_state <= OUT_CTX_WAIT;
          else
            rin.out_state <= OUT_CTX;
          end if;
        end if;

      when OUT_CTX_WAIT =>
        if r.in_state /= IN_DST_ADDR then
          rin.out_state <= OUT_CTX;
        end if;

      when OUT_CTX =>
        if l4_i.ready = '1' then
          rin.out_state <= OUT_PROTO;
          rin.out_left <= 1;
        end if;

      when OUT_PROTO =>
        if l4_i.ready = '1' then
          rin.out_state <= OUT_LEN;
          rin.out_left <= 1;
        end if;

      when OUT_LEN =>
        if l4_i.ready = '1' then
          rin.pdu_len <= r.pdu_len(7 downto 0) & "--------";
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

      when OUT_DATA =>
        if l4_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (l4_i.ready = '1' and r.fifo_fillness = 1) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          elsif r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if l4_i.ready = '1' then
          rin.out_state <= OUT_RESET;
        end if;
    end case;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= l2_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= l2_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.out_state is
      when OUT_RESET | OUT_CTX_WAIT =>
        l4_o <= committed_req_idle_c;

      when OUT_HEADER_PEER_IP | OUT_DATA =>
        l4_o <= committed_flit(
          data => r.fifo(0),
          valid => r.fifo_fillness /= 0);

      when OUT_CTX =>
        if r.is_bcast then
          l4_o <= committed_flit(x"01");
        else
          l4_o <= committed_flit(x"00");
        end if;

      when OUT_PROTO =>
        l4_o <= committed_flit(r.proto);

      when OUT_LEN =>
        l4_o <= committed_flit(std_ulogic_vector(r.pdu_len(15 downto 8)));

      when OUT_COMMIT =>
        l4_o <= committed_commit(true);
        
      when OUT_CANCEL =>
        l4_o <= committed_commit(false);
    end case;

    case r.in_state is
      when IN_RESET | IN_CANCEL | IN_COMMIT =>
        l2_o <= committed_accept(false);

      when IN_VER_LEN | IN_TOS | IN_TOTAL_LEN
        | IN_IDENTIFICATION | IN_FRAG_OFF | IN_TTL | IN_PROTO
        | IN_CHKSUM | IN_DST_ADDR | IN_OPTS
        | IN_DROP =>
        l2_o <= committed_accept(true);

      when IN_HEADER | IN_SRC_ADDR | IN_DATA =>
        l2_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;

end architecture;
