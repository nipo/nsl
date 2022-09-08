library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, work, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use work.flit.all;
use nsl_data.bytestream.all;

entity mii_flit_to_committed is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    flit_i : in mii_flit_t;
    valid_i : in std_ulogic;

    committed_o : out nsl_bnoc.committed.committed_req;
    committed_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mii_flit_to_committed is

  type in_state_t is (
    IN_RESET,
    IN_IDLE,
    IN_PRE,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_IDLE,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state : in_state_t;
    in_overflow : boolean;
    in_error_seen : boolean;

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

  transition: process(r, flit_i, valid_i, committed_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;

      when IN_IDLE =>
        if valid_i = '1' and flit_i.valid = '1' then
          rin.in_state <= IN_PRE;
          rin.in_overflow <= false;
          rin.in_error_seen <= false;
        end if;

      when IN_PRE =>
        if valid_i = '1' then
          if flit_i.valid = '1' and flit_i.error = '0' then
            if flit_i.data = x"55" then
              rin.in_state <= IN_PRE;
            elsif flit_i.data = x"d5" then
              rin.in_state <= IN_DATA;
            else
              rin.in_state <= IN_IDLE;
            end if;
          else
            rin.in_state <= IN_IDLE;
          end if;
        end if;

      when IN_DATA =>
        if valid_i = '1' then
          if flit_i.valid = '1' and flit_i.error = '0' then
            fifo_push := true;
          elsif flit_i.valid = '0' and flit_i.error = '1' then
            rin.in_state <= IN_CANCEL;
          elsif flit_i.valid = '1' and flit_i.error = '1' then
            rin.in_error_seen <= true;
            fifo_push := true;
            -- GMII / RGMII:
            -- - 00-0d, 10-1e, 20-fe: reserved
            -- - 0e: false carrier
            -- - 0f: carrier extend
            -- - 1f: carrier error extend
            -- - ff: carrier sense
          else -- valid = '0', error = '0'
            rin.in_state <= IN_COMMIT;
          end if;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_IDLE and r.fifo_fillness = 0 then
          rin.in_state <= IN_IDLE;
        end if;

      when IN_CANCEL =>
        if valid_i = '1' and flit_i.valid = '0' and flit_i.error = '0' then
          rin.in_state <= IN_IDLE;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_IDLE;

      when OUT_IDLE =>
        if r.in_state = IN_DATA and r.fifo_fillness > 0 then
          rin.out_state <= OUT_DATA;
          if committed_i.ready = '1' then
            fifo_pop := true;
          end if;
        end if;

      when OUT_DATA =>
        if committed_i.ready = '1' and r.fifo_fillness > 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (committed_i.ready = '1' and r.fifo_fillness = 1) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          elsif r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if committed_i.ready = '1' then
          rin.out_state <= OUT_IDLE;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= flit_i.data;
    elsif fifo_push then
      if r.fifo_fillness = fifo_depth_c then
        rin.in_overflow <= true;
      else
        rin.fifo(r.fifo_fillness) <= flit_i.data;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      end if;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.out_state is
      when OUT_RESET =>
        committed_o.valid <= '0';
        committed_o.data <= "--------";
        committed_o.last <= '-';

      when OUT_IDLE | OUT_DATA =>
        committed_o.valid <= to_logic(r.fifo_fillness /= 0);
        committed_o.last <= '0';
        committed_o.data <= r.fifo(0);

      when OUT_COMMIT =>
        committed_o.valid <= '1';
        committed_o.last <= '1';
        committed_o.data <= x"00";
        committed_o.data(0) <= to_logic(not r.in_overflow and not r.in_error_seen);
        
      when OUT_CANCEL =>
        committed_o.valid <= '1';
        committed_o.last <= '1';
        committed_o.data <= x"00";
    end case;
  end process;
  
end architecture;
