library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity committed_header_extractor is
  generic(
    header_length_c : positive
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    header_o : out byte_string(0 to header_length_c-1);
    valid_o : out std_ulogic;
    
    in_i   : in  committed_req;
    in_o   : out committed_ack;

    out_o  : out committed_req;
    out_i  : in committed_ack
    );
end entity;

architecture beh of committed_header_extractor is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to header_length_c-1;

    header: byte_string(0 to header_length_c-1);
    header_valid: boolean;
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_state : out_state_t;
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

  transition: process(r, in_i, out_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    rin.header_valid <= false;
    
    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_HEADER;
        rin.in_left <= header_length_c-1;
        rin.fifo_fillness <= 0;

      when IN_HEADER =>
        if in_i.valid = '1' then
          rin.header <= shift_left(r.header, in_i.data);
          if in_i.last = '1' then
            rin.in_left <= header_length_c -1;
          elsif r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
          else
            rin.header_valid <= true;
            rin.in_state <= IN_DATA;
          end if;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and in_i.valid = '1' then
          if in_i.last = '0' then
            fifo_push := true;
          elsif in_i.data(0) = '1' then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if (r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL)
          and out_i.ready = '1' then
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c-1;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_DATA;

      when OUT_DATA =>
        if r.fifo_fillness > 0 and out_i.ready = '1' then
          fifo_pop := true;
        end if;

        if (r.fifo_fillness = 0 or (r.fifo_fillness = 1 and out_i.ready = '1')) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          end if;
          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if out_i.ready = '1' then
          rin.out_state <= OUT_DATA;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= in_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= in_i.data;
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
        out_o <= committed_req_idle_c;
        
      when OUT_DATA =>
        out_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_COMMIT =>
        out_o <= committed_commit(true);

      when OUT_CANCEL =>
        out_o <= committed_commit(false);
    end case;

    case r.in_state is
      when IN_RESET | IN_COMMIT | IN_CANCEL =>
        in_o.ready <= '0';

      when IN_HEADER =>
        in_o.ready <= '1';
        
      when IN_DATA =>
        in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;

    header_o <= r.header;
    valid_o <= to_logic(r.header_valid);
  end process;
  
end architecture;
