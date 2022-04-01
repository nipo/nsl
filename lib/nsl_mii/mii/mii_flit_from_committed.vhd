library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_mii, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use nsl_mii.mii.all;
use nsl_data.bytestream.all;

entity mii_flit_from_committed is
  generic(
    ipg_c : natural := 96 -- bits
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    committed_i : in nsl_bnoc.committed.committed_req;
    committed_o : out nsl_bnoc.committed.committed_ack;

    flit_o : out mii_flit_t;
    ready_i : in std_ulogic
    );
end entity;

architecture beh of mii_flit_from_committed is
  
  type in_state_t is (
    IN_RESET,
    IN_IDLE,
    IN_DATA,
    IN_CANCEL,
    IN_COMMIT
    );
  
  type out_state_t is (
    OUT_RESET,
    OUT_IPG,
    OUT_IDLE,
    OUT_PRE,
    OUT_SFD,
    OUT_DATA,
    OUT_ERROR
    );

  constant pre_count_c : integer := 8;
  constant out_ctr_max_c : integer := nsl_math.arith.max(ipg_c/8, pre_count_c);
  constant fifo_depth_c : integer := 2;
  
  type regs_t is
  record
    in_state : in_state_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    fifo_underrun: boolean;

    out_counter : natural range 0 to out_ctr_max_c-1;
    out_state : out_state_t;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
      r.fifo_fillness <= 0;
    end if;
  end process;

  transition: process(r, committed_i, ready_i)
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;

      when IN_IDLE =>
        if committed_i.valid = '1' then
          rin.in_state <= IN_DATA;
          rin.fifo_underrun <= false;
          fifo_push := true;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and committed_i.valid = '1' then
          if committed_i.last = '0' then
            fifo_push := true;
          elsif committed_i.data(0) = '1' then
            rin.in_state <= IN_COMMIT;
          else
            -- This should not go out, but avoid underrun to have
            -- error signaled within the packet
            fifo_push := true;
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_CANCEL =>
        if r.out_state = OUT_ERROR then
          rin.in_state <= IN_IDLE;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_IPG then
          rin.in_state <= IN_IDLE;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_IPG;
        rin.out_counter <= ipg_c / 8 - 1;

      when OUT_IPG =>
        if r.out_counter = 0 then
          rin.out_state <= OUT_IDLE;
        else
          rin.out_counter <= r.out_counter - 1;
        end if;

      when OUT_IDLE =>
        if r.fifo_fillness > 0 then
          rin.out_state <= OUT_PRE;
          rin.out_counter <= pre_count_c - 1;
        end if;

      when OUT_PRE =>
        if ready_i = '1' then
          if r.out_counter = 0 then
            rin.out_state <= OUT_SFD;
          else
            rin.out_counter <= r.out_counter - 1;
          end if;
        end if;

      when OUT_SFD =>
        if ready_i = '1' then
          rin.out_state <= OUT_DATA;
        end if;

      when OUT_DATA =>
        if r.fifo_fillness > 0 and ready_i = '1' then
          fifo_pop := true;
        end if;
        
        if (r.fifo_fillness = 1 and ready_i = '1')
          or r.fifo_fillness = 0 then
          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_ERROR;
            rin.out_counter <= ipg_c / 8 - 1;
          elsif r.in_state = IN_COMMIT then
            rin.out_state <= OUT_IPG;
            rin.out_counter <= ipg_c / 8 - 1;
          end if;
        end if;

      when OUT_ERROR =>
        if ready_i = '1' then
          if r.out_counter /= 0 then
            rin.out_counter <= r.out_counter - 1;
          else
            rin.out_state <= OUT_IPG;
            rin.out_counter <= ipg_c / 8 - 1;
          end if;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= committed_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= committed_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      if r.fifo_fillness = 0 then
        rin.fifo_underrun <= true;
      else
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;
    end if;
  end process;
  
  moore: process(r)
  begin
    case r.in_state is
      when IN_RESET | IN_COMMIT | IN_CANCEL =>
        committed_o.ready <= '0';

      when IN_IDLE | IN_DATA =>
        committed_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET | OUT_IPG | OUT_IDLE =>
        flit_o.valid <= '0';
        flit_o.error <= '0';
        flit_o.data <= x"00";

      when OUT_DATA =>
        if r.fifo_underrun then
          flit_o.valid <= '1';
          flit_o.error <= '1';
          flit_o.data <= x"00";
        else
          flit_o.valid <= to_logic(r.fifo_fillness /= 0);
          flit_o.error <= '0';
          flit_o.data <= r.fifo(0);
        end if;

      when OUT_PRE =>
        flit_o.valid <= '1';
        flit_o.error <= '0';
        flit_o.data <= x"55";

      when OUT_SFD =>
        flit_o.valid <= '1';
        flit_o.error <= '0';
        flit_o.data <= x"d5";

      when OUT_ERROR =>
        flit_o.valid <= '1';
        flit_o.error <= '1';
        flit_o.data <= x"00";
    end case;
  end process;

end architecture;
