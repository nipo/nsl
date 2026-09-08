library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, work, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use work.flit.all;
use nsl_data.bytestream.all;

entity mii_flit_from_axi_stream is
  generic(
    config_c: nsl_amba.axi4_stream.config_t;
    ipg_c : natural := 96; -- bits
    pre_count_c : natural := 8; -- flits, not including SFD
    handle_underrun_c: boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    stream_i : in nsl_amba.axi4_stream.master_t;
    stream_o : out nsl_amba.axi4_stream.slave_t;

    error_o : out std_ulogic;
    sfd_o : out std_ulogic;
    packet_o : out std_ulogic;
    flit_o : out mii_flit_t;
    ready_i : in std_ulogic
    );
begin

  assert config_c.data_width = 1
    and config_c.user_width = 1
    and has_last = 1
    report "Bad AXI configuration, need data_width=1, user_width=1 and last"
    severity failure;

end entity;

architecture beh of mii_flit_from_axi_stream is
  
  type in_state_t is (
    IN_RESET,
    IN_IDLE,
    IN_DATA,
    IN_COMMIT
    );
  
  type out_state_t is (
    OUT_RESET,
    OUT_IPG,
    OUT_IDLE,
    OUT_PRE,
    OUT_SFD,
    OUT_DATA
    );

  constant out_ctr_max_c : integer := nsl_math.arith.max(ipg_c/8, pre_count_c);
  constant fifo_depth_c : integer := 8;
  
  type regs_t is
  record
    in_state : in_state_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_counter : natural range 0 to out_ctr_max_c-1;
    out_state : out_state_t;

    error: boolean;
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

  transition: process(r, stream_i, ready_i)
    variable fifo_push, fifo_pop, err: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    err := false;
    if config_c.user_width >= 1 then
      err := user(config_c, stream_i)(0) /= '0';
    end if;
    
    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;

      when IN_IDLE =>
        if stream_i.valid = '1' then
          rin.in_state <= IN_DATA;
          rin.fifo_underrun <= false;
          fifo_push := true;
          rin.error <= err;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and is_valid(config_c, stream_i) then
          rin.error <= r.error or err;
          fifo_push := true;

          if is_last(config_c, stream_i) then
            rin.in_state <= IN_COMMIT;
          end if;
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
        -- The gap is counted in transmitted byte times, so it must
        -- advance at the flit consumption rate, not the core clock.
        if ready_i = '1' then
          if r.out_counter = 0 then
            rin.out_state <= OUT_IDLE;
          else
            rin.out_counter <= r.out_counter - 1;
          end if;
        end if;

      when OUT_IDLE =>
        rin.out_counter <= pre_count_c - 1;
        if r.in_state = IN_DATA then
          rin.out_state <= OUT_PRE;
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
        if ready_i = '1' then
          fifo_pop := true;
        end if;
        
        if r.in_state = IN_COMMIT
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and ready_i = '1')) then
          rin.out_state <= OUT_IPG;
          rin.out_counter <= ipg_c / 8 - 1;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= stream_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= stream_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      if r.fifo_fillness = 0 then
        rin.error <= true;
      else
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;
    end if;
  end process;
  
  moore: process(r)
  begin
    error_o <= to_logic(r.error);
    sfd_o <= '0';

    case r.in_state is
      when IN_RESET | IN_COMMIT =>
        stream_o <= nsl_amba.axi4_stream.accept(config_c, false);

      when IN_IDLE | IN_DATA =>
        stream_o <= nsl_amba.axi4_stream.accept(config_c, r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET | OUT_IPG | OUT_IDLE =>
        flit_o.valid <= '0';
        flit_o.error <= '0';
        flit_o.data <= x"00";
        packet_o <= '0';

      when OUT_PRE =>
        flit_o.valid <= '1';
        flit_o.error <= '0';
        flit_o.data <= x"55";
        packet_o <= '1';

      when OUT_SFD =>
        flit_o.valid <= '1';
        flit_o.error <= '0';
        flit_o.data <= x"d5";
        packet_o <= '1';
        sfd_o <= '1';

      when OUT_DATA =>
        if r.error then
          flit_o.error <= '1';
          flit_o.data <= x"1f";
        else
          flit_o.error <= '0';
          flit_o.data <= r.fifo(0);
        end if;
        flit_o.valid <= to_logic(r.fifo_fillness /= 0);
        packet_o <= '1';
    end case;
  end process;
  
end architecture;
