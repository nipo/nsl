library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity committed_header_inserter is
  generic(
    header_length_c : positive
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    header_i : in byte_string(0 to header_length_c-1);
    capture_i : in std_ulogic;
    
    in_i   : in  committed_req;
    in_o   : out committed_ack;

    out_o  : out committed_req;
    out_i  : in committed_ack
    );
end entity;

architecture beh of committed_header_inserter is

  type in_state_t is (
    IN_RESET,
    IN_IDLE,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_IDLE,
    OUT_HEADER,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2+header_length_c;

  type regs_t is
  record
    in_state : in_state_t;
    in_header: byte_string(0 to header_length_c-1);

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_header: byte_string(0 to header_length_c-1);
    out_left : integer range 0 to header_length_c-1;
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
      r.out_state <= OUT_IDLE;
    end if;
  end process;

  transition: process(r, in_i, out_i, header_i, capture_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;

      when IN_IDLE =>
        if capture_i = '1' then
          rin.in_header <= header_i;
        end if;

        rin.fifo_fillness <= 0;
        if in_i.valid = '1' then
          rin.in_state <= IN_DATA;
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
          rin.in_state <= IN_IDLE;
        end if;
    end case;

    case r.out_state is
      when OUT_IDLE =>
        if r.in_state = IN_DATA then
          rin.out_header <= r.in_header;
          rin.out_state <= OUT_HEADER;
          rin.out_left <= header_length_c - 1;
        end if;

      when OUT_HEADER =>
        if out_i.ready = '1' then
          rin.out_header <= shift_left(r.out_header);
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

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
          rin.out_state <= OUT_IDLE;
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
      when OUT_IDLE =>
        out_o <= committed_req_idle_c;

      when OUT_HEADER =>
        out_o <= committed_flit(r.out_header(0));
        
      when OUT_DATA =>
        out_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_COMMIT =>
        out_o <= committed_commit(true);

      when OUT_CANCEL =>
        out_o <= committed_commit(false);
    end case;

    case r.in_state is
      when IN_RESET | IN_IDLE | IN_COMMIT | IN_CANCEL =>
        in_o.ready <= '0';

      when IN_DATA =>
        in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;
  
end architecture;
