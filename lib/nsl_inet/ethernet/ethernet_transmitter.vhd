library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_logic;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ethernet.all;
use nsl_logic.bool.all;

entity ethernet_transmitter is
  generic(
    l1_header_length_c : integer := 0;
    l1_has_fcs_c : boolean := true;
    min_frame_size_c : natural := 64 --bytes
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    l3_type_i : in ethertype_t;
    l3_i : in nsl_bnoc.committed.committed_req;
    l3_o : out nsl_bnoc.committed.committed_ack;

    l1_o : out nsl_bnoc.committed.committed_req;
    l1_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of ethernet_transmitter is

  type in_state_t is (
    IN_RESET,
    IN_HEADER_DADDR,
    IN_CTX,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER_DADDR,
    OUT_SADDR_TYPE,
    OUT_DATA,
    OUT_PAD,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to 5 + l1_header_length_c;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_saddr_type : byte_string(0 to 7);
    out_state : out_state_t;
    out_left : integer range 0 to 7 + l1_header_length_c;
    out_frame_left : integer range 0 to min_frame_size_c - 5;
  end record;

  signal to_fcs_s : nsl_bnoc.committed.committed_bus;

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

  transition: process(r, to_fcs_s.ack, l3_i, local_address_i, l3_type_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_HEADER_DADDR;
        rin.in_left <= 5 + l1_header_length_c;
        rin.fifo_fillness <= 0;

      when IN_HEADER_DADDR =>
        if l3_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;

          if r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
          else
            rin.in_state <= IN_CTX;
          end if;

          if l3_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_CTX =>
        if l3_i.valid = '1' then
          rin.out_saddr_type <= local_address_i & to_be(to_unsigned(l3_type_i, 16));

          rin.in_state <= IN_DATA;
          if l3_i.last = '1' then
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_DATA =>
        if l3_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if l3_i.last = '1' then
            if l3_i.data(0) = '1' then
              rin.in_state <= IN_COMMIT;
            else
              rin.in_state <= IN_CANCEL;
            end if;
          else
            fifo_push := true;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_CANCEL or r.out_state = OUT_COMMIT then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_HEADER_DADDR;
        rin.out_left <= 5 + l1_header_length_c;
        rin.out_frame_left <= min_frame_size_c - 5;

      when OUT_HEADER_DADDR =>
        if to_fcs_s.ack.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;

          if r.out_frame_left /= 0 then
            rin.out_frame_left <= r.out_frame_left - 1;
          end if;

          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_SADDR_TYPE;
            rin.out_left <= 7;
          end if;
        end if;

        if r.in_state = IN_CANCEL then
          rin.out_state <= OUT_CANCEL;
        end if;

      when OUT_SADDR_TYPE =>
        if to_fcs_s.ack.ready = '1' then
          if r.out_frame_left /= 0 then
            rin.out_frame_left <= r.out_frame_left - 1;
          end if;

          rin.out_saddr_type <= shift_left(r.out_saddr_type);
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

      when OUT_DATA =>
        if to_fcs_s.ack.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;

          if r.out_frame_left /= 0 then
            rin.out_frame_left <= r.out_frame_left - 1;
          end if;
        end if;

        if r.in_state = IN_CANCEL then
          rin.out_state <= OUT_CANCEL;
        end if;

        if (to_fcs_s.ack.ready = '1' and r.fifo_fillness = 1) or r.fifo_fillness = 0 then
          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          elsif r.in_state = IN_COMMIT then
            if r.out_frame_left /= 0 then
              rin.out_state <= OUT_PAD;
            else
              rin.out_state <= OUT_COMMIT;
            end if;
          end if;
        end if;

      when OUT_PAD =>
        if to_fcs_s.ack.ready = '1' then
          if r.out_frame_left /= 0 then
            rin.out_frame_left <= r.out_frame_left - 1;
          else
            if r.in_state = IN_CANCEL then
              rin.out_state <= OUT_CANCEL;
            elsif r.in_state = IN_COMMIT then
              rin.out_state <= OUT_COMMIT;
            end if;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if to_fcs_s.ack.ready = '1' then
          rin.out_state <= OUT_RESET;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= l3_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= l3_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  mealy: process(r, to_fcs_s.ack, l3_i) is
  begin
    to_fcs_s.req.valid <= '0';
    to_fcs_s.req.last <= '-';
    to_fcs_s.req.data <= (others => '-');
    l3_o.ready <= '0';

    case r.in_state is
      when IN_RESET | IN_CANCEL | IN_COMMIT =>
        null;

      when IN_HEADER_DADDR | IN_DATA =>
        l3_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);

      when IN_CTX =>
        l3_o.ready <= '1';
    end case;

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_HEADER_DADDR | OUT_DATA =>
        to_fcs_s.req.data <= r.fifo(0);
        to_fcs_s.req.last <= '0';
        to_fcs_s.req.valid <= to_logic(r.fifo_fillness /= 0);

      when OUT_SADDR_TYPE =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '0';
        to_fcs_s.req.data <= r.out_saddr_type(0);

      when OUT_PAD =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '0';
        to_fcs_s.req.data <= x"00";

      when OUT_COMMIT =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '1';
        to_fcs_s.req.data <= x"01";

      when OUT_CANCEL =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '1';
        to_fcs_s.req.data <= x"00";
    end case;
  end process;

  has_fcs: if l1_has_fcs_c
  generate
    fcs: nsl_bnoc.crc.crc_committed_adder
      generic map(
        header_length_c => l1_header_length_c,
        params_c => fcs_params_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        in_i => to_fcs_s.req,
        in_o => to_fcs_s.ack,

        out_i => l1_i,
        out_o => l1_o
        );
  end generate;

  no_fcs: if not l1_has_fcs_c
  generate
    to_fcs_s.ack <= l1_i;
    l1_o <= to_fcs_s.req;
  end generate;
      
end architecture;
