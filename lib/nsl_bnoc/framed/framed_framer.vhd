library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity framed_framer is
  generic(
    timeout_c : natural;
    max_length_c : natural := 1024
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i   : in  std_ulogic;

    pipe_i   : in  pipe_req_t;
    pipe_o   : out pipe_ack_t;

    frame_o  : out framed_req;
    frame_i  : in framed_ack
    );
end entity;

architecture rtl of framed_framer is

  type in_state_t is (
    IN_RESET,
    IN_IDLE,
    IN_DATA,
    IN_COMMIT
    );

  type out_state_t is (
    OUT_RESET,
    OUT_DATA,
    OUT_COMMIT
    );

  constant fifo_depth_c : integer := 3;
  
  type regs_t is
  record
    in_state : in_state_t;
    in_timeout : integer range 0 to timeout_c-1;
    in_left : integer range 0 to max_length_c-1;

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

  transition: process(r, frame_i, pipe_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;
        rin.fifo_fillness <= 0;

      when IN_IDLE =>
        if pipe_i.valid = '1' then
          fifo_push := true;
          rin.in_left <= max_length_c-1;
          rin.in_timeout <= timeout_c - 1;
          rin.in_state <= IN_DATA;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and pipe_i.valid = '1' then
          fifo_push := true;
          rin.in_timeout <= timeout_c - 1;
          if r.in_left = 0 then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_left <= r.in_left - 1;
          end if;
        elsif r.in_timeout /= 0 then
          rin.in_timeout <= r.in_timeout - 1;
        else
          rin.in_state <= IN_COMMIT;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_RESET then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_DATA;

      when OUT_DATA =>
        if r.fifo_fillness > 1 and frame_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.in_state = IN_COMMIT then
          rin.out_state <= OUT_COMMIT;
        end if;

      when OUT_COMMIT =>
        if r.fifo_fillness > 0 and frame_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0 or
          (r.fifo_fillness = 1 and frame_i.ready = '1') then
          rin.out_state <= OUT_RESET;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      rin.fifo(r.fifo_fillness-1) <= pipe_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= pipe_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.out_state is
      when OUT_RESET =>
        frame_o.data <= "--------";
        frame_o.valid <= '0';
        frame_o.last <= '-';

      when OUT_DATA =>
        frame_o.data <= r.fifo(0);
        frame_o.valid <= to_logic(r.fifo_fillness > 1);
        frame_o.last <= '0';

      when OUT_COMMIT =>
        frame_o.data <= r.fifo(0);
        frame_o.valid <= to_logic(r.fifo_fillness /= 0);
        frame_o.last <= to_logic(r.fifo_fillness = 1);
    end case;

    case r.in_state is
      when IN_RESET | IN_COMMIT =>
        pipe_o.ready <= '0';

      when IN_DATA | IN_IDLE =>
        pipe_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;

end architecture;
