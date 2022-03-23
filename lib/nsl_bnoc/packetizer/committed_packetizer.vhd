library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity committed_packetizer is
  generic(
    header_length_c : natural := 0
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    frame_header_i : in byte_string(0 to header_length_c-1) := (others => x"00");
    frame_valid_i : in std_ulogic := '1';
    
    frame_i   : in  framed_req;
    frame_o   : out framed_ack;

    packet_o  : out committed_req;
    packet_i  : in committed_ack
    );
end entity;

architecture beh of committed_packetizer is

  type in_state_t is (
    IN_RESET,
    IN_IDLE,
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

  constant fifo_depth_c : integer := 3;

  type regs_t is
  record
    in_state : in_state_t;
    in_ctr : integer range 0 to header_length_c-1;

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

  transition: process(r, frame_i, packet_i, frame_valid_i, frame_header_i) is
    variable fifo_push, fifo_pop: boolean;
    variable fifo_data : byte;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    fifo_data := "--------";

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_IDLE;

      when IN_IDLE =>
        rin.fifo_fillness <= 0;
        if frame_i.valid = '1' then
          if header_length_c /= 0 then
            rin.in_state <= IN_HEADER;
            rin.in_ctr <= 0;
          else
            rin.in_state <= IN_DATA;
          end if;
        end if;

      when IN_HEADER =>
        if r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          fifo_data := frame_header_i(r.in_ctr);
          if r.in_ctr /= header_length_c - 1 then
            rin.in_ctr <= r.in_ctr + 1;
          else
            rin.in_state <= IN_DATA;
          end if;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and frame_i.valid = '1' then
          fifo_push := true;
          fifo_data := frame_i.data;
          if frame_i.last = '1' then
            if frame_valid_i = '1' then
              rin.in_state <= IN_COMMIT;
            else
              rin.in_state <= IN_CANCEL;
            end if;
          end if;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_COMMIT and packet_i.ready = '1' then
          rin.in_state <= IN_IDLE;
        end if;

      when IN_CANCEL =>
        if r.out_state = OUT_CANCEL and packet_i.ready = '1' then
          rin.in_state <= IN_IDLE;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_DATA;

      when OUT_DATA =>
        if r.fifo_fillness > 0 and packet_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.in_state = IN_COMMIT
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and packet_i.ready = '1')) then
          rin.out_state <= OUT_COMMIT;
        end if;

        if r.in_state = IN_CANCEL
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and packet_i.ready = '1')) then
          rin.out_state <= OUT_CANCEL;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if packet_i.ready = '1' then
          rin.out_state <= OUT_DATA;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= fifo_data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= fifo_data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    packet_o.data <= "--------";
    packet_o.valid <= '0';
    packet_o.last <= '-';

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_DATA =>
        packet_o.data <= r.fifo(0);
        packet_o.valid <= to_logic(r.fifo_fillness > 0);
        packet_o.last <= '0';

      when OUT_COMMIT =>
        packet_o.data <= x"01";
        packet_o.valid <= '1';
        packet_o.last <= '1';

      when OUT_CANCEL =>
        packet_o.data <= x"00";
        packet_o.valid <= '1';
        packet_o.last <= '1';
    end case;

    case r.in_state is
      when IN_RESET | IN_COMMIT | IN_HEADER | IN_CANCEL | IN_IDLE =>
        frame_o.ready <= '0';

      when IN_DATA =>
        frame_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;
  end process;
  
end architecture;
