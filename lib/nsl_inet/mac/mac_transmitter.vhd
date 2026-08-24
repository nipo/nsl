library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_math, nsl_logic, work;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use work.mac.all;

entity mac_transmitter is
  generic(
    l1_has_fcs_c : boolean := true;
    l1_header_length_c : integer := 0;
    min_frame_size_c : natural := 64 --bytes
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    l2_i : in nsl_bnoc.committed.committed_req;
    l2_o : out nsl_bnoc.committed.committed_ack;

    l1_o : out nsl_bnoc.committed.committed_req;
    l1_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mac_transmitter is

  -- Frame bytes to emit before FCS for reaching minimal frame size,
  -- L1 pre-header excluded.
  constant pad_target_c : integer := min_frame_size_c - 4;

  type state_t is (
    ST_RESET,
    ST_HEADER,
    ST_DATA,
    ST_PAD,
    ST_STATUS
    );

  type regs_t is
  record
    state : state_t;
    header_left : integer range 0 to nsl_math.arith.max(l1_header_length_c-1, 0);
    pad_left : integer range 0 to pad_target_c;
    status : byte;
  end record;

  signal r, rin: regs_t;

  signal to_fcs_s : nsl_bnoc.committed.committed_bus;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, l2_i, to_fcs_s.ack) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.pad_left <= pad_target_c;
        if l1_header_length_c /= 0 then
          rin.state <= ST_HEADER;
          rin.header_left <= l1_header_length_c - 1;
        else
          rin.state <= ST_DATA;
        end if;

      when ST_HEADER =>
        if l2_i.valid = '1' and to_fcs_s.ack.ready = '1' then
          if l2_i.last = '1' then
            rin.state <= ST_RESET;
          elsif r.header_left = 0 then
            rin.state <= ST_DATA;
          else
            rin.header_left <= r.header_left - 1;
          end if;
        end if;

      when ST_DATA =>
        if l2_i.valid = '1' then
          if l2_i.last = '0' then
            if to_fcs_s.ack.ready = '1' and r.pad_left /= 0 then
              rin.pad_left <= r.pad_left - 1;
            end if;
          elsif l2_i.data(0) = '1' and r.pad_left /= 0 then
            -- Committed frame shorter than minimal size, hold status
            -- byte and pad
            rin.status <= l2_i.data;
            rin.state <= ST_PAD;
          elsif to_fcs_s.ack.ready = '1' then
            rin.state <= ST_RESET;
          end if;
        end if;

      when ST_PAD =>
        if to_fcs_s.ack.ready = '1' then
          rin.pad_left <= r.pad_left - 1;
          if r.pad_left = 1 then
            rin.state <= ST_STATUS;
          end if;
        end if;

      when ST_STATUS =>
        if to_fcs_s.ack.ready = '1' then
          rin.state <= ST_RESET;
        end if;
    end case;
  end process;

  mealy: process(r, l2_i, to_fcs_s.ack) is
  begin
    to_fcs_s.req.valid <= '0';
    to_fcs_s.req.last <= '-';
    to_fcs_s.req.data <= (others => '-');
    l2_o.ready <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_HEADER =>
        to_fcs_s.req <= l2_i;
        l2_o.ready <= to_fcs_s.ack.ready;

      when ST_DATA =>
        if l2_i.valid = '1' and l2_i.last = '1'
          and l2_i.data(0) = '1' and r.pad_left /= 0 then
          -- Swallow status byte, padding comes next
          l2_o.ready <= '1';
        else
          to_fcs_s.req <= l2_i;
          l2_o.ready <= to_fcs_s.ack.ready;
        end if;

      when ST_PAD =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '0';
        to_fcs_s.req.data <= x"00";

      when ST_STATUS =>
        to_fcs_s.req.valid <= '1';
        to_fcs_s.req.last <= '1';
        to_fcs_s.req.data <= r.status;
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
