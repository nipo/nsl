library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;

entity committed_prefill_buffer is
  generic(
    prefill_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;
    
    in_i   : in  committed_req;
    in_o   : out committed_ack;

    out_o  : out committed_req;
    out_i  : in committed_ack
    );
end entity;

architecture beh of committed_prefill_buffer is

  type in_state_t is (
    IN_RESET,
    IN_DATA,
    IN_DONE
    );

  type out_state_t is (
    OUT_RESET,
    OUT_PREFILL,
    OUT_DATA,
    OUT_FLUSH,
    OUT_DONE
    );

  constant fifo_depth_c : integer := prefill_count_c+2;
  
  type regs_t is
  record
    in_state : in_state_t;

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

    case r.in_state is
      when IN_RESET =>
        rin.fifo_fillness <= 0;
        rin.in_state <= IN_DATA;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and in_i.valid = '1' then
          fifo_push := true;
          if in_i.last = '1' then
            rin.in_state <= IN_DONE;
          end if;
        end if;
        
      when IN_DONE =>
        if r.out_state = OUT_DONE then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_PREFILL;

      when OUT_PREFILL =>
        if r.fifo_fillness >= prefill_count_c then
          rin.out_state <= OUT_DATA;
        end if;
        if r.in_state = IN_DONE then
          rin.out_state <= OUT_FLUSH;
        end if;

      when OUT_DATA =>
        if r.fifo_fillness > 1 and out_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.in_state = IN_DONE then
          rin.out_state <= OUT_FLUSH;
        end if;

      when OUT_FLUSH =>
        if r.fifo_fillness > 0 and out_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
            or (r.fifo_fillness = 1 and out_i.ready = '1') then
          rin.out_state <= OUT_DONE;
        end if;

      when OUT_DONE =>
        if r.in_state = IN_DONE then
          rin.out_state <= OUT_RESET;
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
      when OUT_RESET | OUT_DONE | OUT_PREFILL =>
        out_o <= committed_flit(data => "--------", valid => false);

      when OUT_DATA =>
        out_o <= committed_flit(data => r.fifo(0),
                                valid => r.fifo_fillness > 1,
                                last => false);

      when OUT_FLUSH =>
        out_o <= committed_flit(data => r.fifo(0),
                                valid => r.fifo_fillness > 0,
                                last => r.fifo_fillness = 1);
    end case;

    case r.in_state is
      when IN_RESET | IN_DONE =>
        in_o.ready <= '0';

      when IN_DATA =>
        in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;
end architecture;
