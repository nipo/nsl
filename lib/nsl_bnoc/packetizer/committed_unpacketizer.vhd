library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity committed_unpacketizer is
  generic(
    header_length_c : natural := 0
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    packet_i  : in  committed_req;
    packet_o  : out committed_ack;
    
    frame_header_o : out byte_string(0 to header_length_c-1);
    frame_valid_o : out std_ulogic;

    frame_o   : out framed_req;
    frame_i   : in framed_ack
    );
end entity;

architecture beh of committed_unpacketizer is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_DATA,
    IN_COMMIT
    );

  type out_state_t is (
    OUT_DATA,
    OUT_COMMIT
    );

  constant fifo_depth_c : integer := 3;

  type regs_t is
  record
    in_state : in_state_t;
    in_ctr : integer range 0 to header_length_c-1;
    in_header : byte_string(0 to header_length_c-1);
    in_valid : boolean;

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
      r.fifo_fillness <= 0;
      r.in_state <= IN_RESET;
      r.out_state <= OUT_DATA;
    end if;
  end process;

  transition: process(r, frame_i, packet_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_valid <= true;
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_ctr <= 0;
        else
          rin.in_state <= IN_DATA;
        end if;

      when IN_HEADER =>
        if packet_i.valid = '1' then
          if r.in_ctr /= header_length_c - 1 then
            rin.in_ctr <= r.in_ctr + 1;
            rin.in_header(r.in_ctr) <= packet_i.data;
          else
            rin.in_state <= IN_DATA;
          end if;

          if packet_i.last = '1' then
            rin.in_state <= IN_RESET;
          end if;
        end if;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and packet_i.valid = '1' then
          if packet_i.last = '1' then
            rin.in_state <= IN_COMMIT;
            rin.in_valid <= packet_i.data(0) = '1';
          else
            fifo_push := true;
          end if;
        end if;

      when IN_COMMIT =>
        if r.fifo_fillness = 0 then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
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

        if (r.fifo_fillness = 1 and frame_i.ready = '1')
          or r.fifo_fillness = 0 then
          rin.out_state <= OUT_DATA;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= packet_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= packet_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.out_state is
      when OUT_DATA =>
        frame_o.data <= r.fifo(0);
        frame_o.valid <= to_logic(r.fifo_fillness > 1);
        frame_o.last <= '0';

      when OUT_COMMIT =>
        frame_o.data <= r.fifo(0);
        frame_o.valid <= to_logic(r.fifo_fillness > 0);
        frame_o.last <= to_logic(r.fifo_fillness = 1);
    end case;

    case r.in_state is
      when IN_RESET | IN_COMMIT =>
        packet_o.ready <= '0';

      when IN_HEADER =>
        packet_o.ready <= '1';
        
      when IN_DATA =>
        packet_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;

    frame_header_o <= r.in_header;
    frame_valid_o <= to_logic(r.in_valid);
  end process;
  
end architecture;
