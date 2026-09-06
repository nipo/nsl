library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_logic, nsl_memory;
use nsl_logic.bool.all;
use nsl_amba.axi4_stream.all;

entity axi4_stream_prefill_buffer is
    generic (
        config_c    : config_t;
        prefill_count_c : natural
    );
    port (
        reset_n_i : in std_ulogic;
        clock_i   : in std_ulogic;

        in_i : in  master_t;
        in_o : out slave_t;

        out_o : out master_t;
        out_i : in  slave_t
    );
end entity;

architecture beh of axi4_stream_prefill_buffer is

  -- This is an elasticity buffer meant to absorb short upstream
  -- bubbles before a flow-control-less consumer, not a
  -- store-and-forward fifo. Storage is a shift-register fifo capped
  -- at 16 words; designs needing whole-frame buffering should use a
  -- RAM-backed fifo instead.
  constant fifo_depth_c : integer := prefill_count_c + 2;

  -- Beats are stored packed; last is not stored, it is regenerated on
  -- the final beat of the flush.
  constant elements_c : string := "idskou";
  constant word_width_c : natural := vector_length(config_c, elements_c);

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

  type regs_t is
  record
    in_state : in_state_t;
    out_state : out_state_t;
  end record;

  signal r, rin : regs_t;

  signal fifo_in_data_s, fifo_out_data_s : std_ulogic_vector(0 to word_width_c-1);
  signal fifo_in_valid_s, fifo_in_ready_s : std_ulogic;
  signal fifo_out_valid_s, fifo_out_ready_s : std_ulogic;
  signal fifo_fill_s : std_ulogic_vector(0 to fifo_depth_c);

  function fill_at_least(fill : std_ulogic_vector;
                         count : integer) return boolean
  is
  begin
    for i in fill'range
    loop
      if i >= count and fill(i) = '1' then
        return true;
      end if;
    end loop;
    return false;
  end function;

begin

  assert prefill_count_c >= 1 and prefill_count_c <= 14
    report "prefill_count_c must be in 1 to 14, this is an elasticity "
    & "buffer, not a store-and-forward fifo"
    severity failure;

  regs : process (clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
    end if;
  end process;

  -- Guarded so that an oversized prefill_count_c reaches the assert
  -- above instead of the generic bound check of the fifo.
  depth_ok : if fifo_depth_c <= 16 generate
    fifo : nsl_memory.fifo.fifo_shift_register
      generic map(
        data_width_c => word_width_c,
        word_count_c => fifo_depth_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        in_data_i => fifo_in_data_s,
        in_valid_i => fifo_in_valid_s,
        in_ready_o => fifo_in_ready_s,

        out_data_o => fifo_out_data_s,
        out_valid_o => fifo_out_valid_s,
        out_ready_i => fifo_out_ready_s,

        fill_o => fifo_fill_s
        );
  end generate;

  fifo_in_data_s <= vector_pack(config_c, elements_c, in_i);

  transition : process (r, in_i, out_i,
                        fifo_in_ready_s, fifo_fill_s) is
  begin
    rin <= r;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_DATA;

      when IN_DATA =>
        if is_valid(config_c, in_i) and fifo_in_ready_s = '1'
          and is_last(config_c, in_i) then
          rin.in_state <= IN_DONE;
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
        if fill_at_least(fifo_fill_s, prefill_count_c) then
          rin.out_state <= OUT_DATA;
        end if;
        if r.in_state = IN_DONE then
          rin.out_state <= OUT_FLUSH;
        end if;

      when OUT_DATA =>
        if r.in_state = IN_DONE then
          rin.out_state <= OUT_FLUSH;
        end if;

      when OUT_FLUSH =>
        if fifo_fill_s(0) = '1'
          or (fifo_fill_s(1) = '1' and out_i.ready = '1') then
          rin.out_state <= OUT_DONE;
        end if;

      when OUT_DONE =>
        if r.in_state = IN_DONE then
          rin.out_state <= OUT_RESET;
        end if;
    end case;
  end process;

  mealy : process (r, in_i, out_i,
                   fifo_in_ready_s, fifo_out_valid_s,
                   fifo_out_data_s, fifo_fill_s) is
  begin
    out_o <= transfer_defaults(config_c);
    fifo_out_ready_s <= '0';

    case r.out_state is
      when OUT_DATA =>
        -- Hold the newest beat back so that the final beat of the
        -- packet is only ever emitted in OUT_FLUSH, where it gets its
        -- last flag.
        out_o <= transfer(config_c,
                          src => vector_unpack(config_c, elements_c,
                                               fifo_out_data_s),
                          force_valid => true,
                          valid => fifo_fill_s(0) = '0'
                                   and fifo_fill_s(1) = '0',
                          force_last => true,
                          last => false);
        if fifo_fill_s(0) = '0' and fifo_fill_s(1) = '0' then
          fifo_out_ready_s <= out_i.ready;
        end if;

      when OUT_FLUSH =>
        out_o <= transfer(config_c,
                          src => vector_unpack(config_c, elements_c,
                                               fifo_out_data_s),
                          force_valid => true,
                          valid => fifo_out_valid_s = '1',
                          force_last => true,
                          last => fifo_fill_s(1) = '1');
        fifo_out_ready_s <= out_i.ready;

      when others =>
        null;
    end case;

    case r.in_state is
      when IN_RESET | IN_DONE =>
        in_o.ready <= '0';
        fifo_in_valid_s <= '0';

      when IN_DATA =>
        in_o.ready <= fifo_in_ready_s;
        fifo_in_valid_s <= to_logic(is_valid(config_c, in_i));
    end case;
  end process;

end architecture;
