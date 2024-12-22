library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;

entity crc_framed_adder is
  generic(
    header_length_c : natural := 0;

    params_c : crc_params_t
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;
    
    in_i   : in  framed_req;
    in_o   : out framed_ack;

    out_o  : out framed_req;
    out_i  : in framed_ack
    );
end entity;

architecture beh of crc_framed_adder is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_DATA,
    IN_COMMIT
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER,
    OUT_DATA,
    OUT_CRC
    );

  constant crc_byte_count_c : integer := crc_byte_length(params_c);
  constant max_step_c : integer := nsl_math.arith.max(crc_byte_count_c, header_length_c);
  constant fifo_depth_c : integer := 2;
  
  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    
    out_state : out_state_t;
    crc : crc_state_t;
    check: byte_string(0 to crc_byte_count_c-1);
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

  transition: process(r, in_i, out_i) is
    variable fifo_push, fifo_pop: boolean;
    variable c : crc_state_t;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    c := r.crc;

    case r.in_state is
      when IN_RESET =>
        rin.fifo_fillness <= 0;
        if header_length_c = 0 then
          rin.in_state <= IN_DATA;
        else
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c-1;
        end if;

      when IN_HEADER =>
        if r.fifo_fillness < fifo_depth_c and in_i.valid = '1' then
          if in_i.last = '1' then
            rin.in_state <= IN_COMMIT;
          elsif r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
            fifo_push := true;
          else
            rin.in_state <= IN_DATA;
            fifo_push := true;
          end if;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and in_i.valid = '1' then
          fifo_push := true;
          if in_i.last = '1' then
            rin.in_state <= IN_COMMIT;
          end if;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_CRC and r.out_left = 0 and out_i.ready = '1' then
          rin.fifo_fillness <= 0;
          if header_length_c = 0 then
            rin.in_state <= IN_DATA;
          else
            rin.in_state <= IN_HEADER;
            rin.in_left <= header_length_c-1;
          end if;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        if header_length_c = 0 then
          rin.out_state <= OUT_DATA;
          c := crc_init(params_c);
        else
          rin.out_state <= OUT_HEADER;
          rin.out_left <= header_length_c-1;
        end if;

      when OUT_HEADER =>
        if r.fifo_fillness > 0 and out_i.ready = '1' then
          fifo_pop := true;
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            c := crc_init(params_c);
            rin.out_state <= OUT_DATA;
          end if;
        end if;

      when OUT_DATA =>
        if r.fifo_fillness > 0 and out_i.ready = '1' then
          fifo_pop := true;
          c := crc_update(params_c, c, r.fifo(0));
        end if;

        if r.in_state = IN_COMMIT
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and out_i.ready = '1')) then
          rin.check <= crc_spill(params_c, c);
          rin.out_state <= OUT_CRC;
          rin.out_left <= crc_byte_count_c - 1;
        end if;

      when OUT_CRC =>
        if out_i.ready = '1' then
          if r.out_left /= 0 then
            rin.check <= shift_left(r.check);
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_RESET;
          end if;
        end if;
    end case;

    rin.crc <= c;
    
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
        out_o.valid <= '0';
        out_o.data <= "--------";
        out_o.last <= '-';

      when OUT_HEADER | OUT_DATA =>
        out_o.valid <= to_logic(r.fifo_fillness /= 0);
        out_o.last <= '0';
        out_o.data <= r.fifo(0);

      when OUT_CRC =>
        out_o.valid <= '1';
        out_o.last <= to_logic(r.out_left = 0);
        out_o.data <= first_left(r.check);
    end case;

    case r.in_state is
      when IN_RESET =>
        in_o.ready <= '0';

      when IN_HEADER | IN_DATA =>
        in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);

      when IN_COMMIT =>
        in_o.ready <= '0';
    end case;
  end process;
end architecture;
