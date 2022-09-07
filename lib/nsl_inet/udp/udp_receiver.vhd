library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math, nsl_logic;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.udp.all;
use nsl_logic.bool.all;

entity udp_receiver is
  generic(
    header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    l3_i : in committed_req;
    l3_o : out committed_ack;

    l5_o : out committed_req;
    l5_i : in committed_ack
    );
end entity;

architecture beh of udp_receiver is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_PDU_LEN,
    IN_SPORT,
    IN_DPORT,
    IN_LENGTH,
    IN_CHK,
    IN_DATA,
    IN_PAD,
    IN_COMMIT,
    IN_DROP,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;
  constant max_step_c : integer := nsl_math.arith.max(header_length_c, 2);

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    total_len : unsigned(15 downto 0);
    pdu_len: byte_string(0 to 1);
    header: byte_string(0 to header_length_c+3);
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_state : out_state_t;
    out_left : integer range 0 to max_step_c+3;
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

  transition: process(r, l3_i, l5_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c - 1;
        else
          rin.in_state <= IN_PDU_LEN;
          rin.in_left <= 1;
        end if;

      when IN_HEADER =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.header <= shift_left(r.header, l3_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_PDU_LEN;
              rin.in_left <= 1;
            end if;
          end if;
        end if;

      when IN_PDU_LEN =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.pdu_len <= shift_left(r.pdu_len, l3_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_SPORT;
              rin.in_left <= 1;
            end if;
          end if;
        end if;

      when IN_SPORT =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.header <= shift_left(r.header, l3_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_DPORT;
              rin.in_left <= 1;
            end if;
          end if;
        end if;

      when IN_DPORT =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.header <= shift_left(r.header, l3_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_LENGTH;
              rin.in_left <= 1;
            end if;
          end if;
        end if;

      when IN_LENGTH =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.total_len <= r.total_len(7 downto 0) & unsigned(l3_i.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_state <= IN_CHK;
              rin.in_left <= 1;
            end if;
          end if;
        end if;

      when IN_CHK =>
        if l3_i.valid = '1' then
          if l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          else
            if r.total_len > from_be(r.pdu_len) then
              rin.in_state <= IN_DROP;
            elsif r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
              rin.total_len <= r.total_len - 8;
            else
              if r.total_len = 0 then
                rin.in_state <= IN_PAD;
              else
                rin.in_state <= IN_DATA;
                rin.total_len <= r.total_len - 1;
              end if;
            end if;
          end if;
        end if;
        
      when IN_DATA =>
        if l3_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if l3_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          else
            fifo_push := true;
            if r.total_len = 0 then
              rin.in_state <= IN_PAD;
            else
              rin.total_len <= r.total_len - 1;
            end if;
          end if;
        end if;
          
      when IN_PAD =>
        if l3_i.valid = '1' and l3_i.last = '1' then
          if l3_i.data = x"01" then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_state <= IN_CANCEL;
          end if;
        end if;
          
      when IN_DROP =>
        if l3_i.valid = '1' and l3_i.last = '1' then
          rin.in_state <= IN_RESET;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
          rin.in_state <= IN_RESET;
        end if;
          
    end case;
    
    case r.out_state is
      when OUT_RESET =>
        if r.in_state = IN_DATA or r.in_state = IN_PAD then
          rin.out_state <= OUT_HEADER;
          rin.out_left <= header_length_c + 3;
        end if;

      when OUT_HEADER =>
        if l5_i.ready = '1' then
          rin.header <= shift_left(r.header);
          if r.out_left = 0 then
            rin.out_state <= OUT_DATA;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_DATA =>
        if l5_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (l5_i.ready = '1' and r.fifo_fillness = 1) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          elsif r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if l5_i.ready = '1' then
          rin.out_state <= OUT_RESET;
        end if;
    end case;
    
    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= l3_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= l3_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.out_state is
      when OUT_RESET =>
        l5_o <= committed_req_idle_c;
        
      when OUT_HEADER =>
        l5_o <= committed_flit(r.header(0));

      when OUT_DATA =>
        l5_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_COMMIT =>
        l5_o <= committed_commit(true);
        
      when OUT_CANCEL =>
        l5_o <= committed_commit(false);
    end case;

    case r.in_state is
      when IN_RESET | IN_CANCEL | IN_COMMIT =>
        l3_o <= committed_accept(false);

      when IN_HEADER | IN_SPORT | IN_DPORT | IN_LENGTH | IN_CHK
        | IN_PAD | IN_DROP | IN_PDU_LEN =>
        l3_o <= committed_accept(true);

      when IN_DATA =>
        l3_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;

end architecture;
