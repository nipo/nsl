library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;

entity framed_chunker is
  generic(
    max_txn_length_l2_c : natural range 2 to 14 := 10
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    in_i : in framed_req_t;
    in_o : out framed_ack_t;

    out_o : out nsl_bnoc.pipe.pipe_req_t;
    out_i : in nsl_bnoc.pipe.pipe_ack_t
    );
end entity;

architecture rtl of framed_chunker is

  signal data_in_s, data_out_s: nsl_bnoc.pipe.pipe_bus_t;

  type state_t is (
    ST_RESET,
    ST_EMPTY,
    ST_FILL,
    ST_SIZE_H,
    ST_SIZE_L,
    ST_FLUSH
    );

  constant idle_count_c: integer := 4;

  type regs_t is record
    state: state_t;
    count: unsigned(max_txn_length_l2_c-1 downto 0);
    last: std_ulogic;
    idle_left: integer range 0 to idle_count_c-1;
  end record;

  signal r, rin : regs_t;

  -- Size as it is conveyed in the 14-bit, off-by-one header field.
  signal count_s : unsigned(13 downto 0);

begin

  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  count_s <= resize(r.count, count_s'length);

  transition: process(in_i, out_i, r, data_in_s, data_out_s)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if in_i.valid = '1' and data_in_s.ack.ready = '1' then
          rin.idle_left <= idle_count_c-1;
          rin.count <= (others => '0');
          rin.last <= in_i.last;
          rin.state <= ST_FILL;
          if in_i.last = '1' then
            rin.state <= ST_SIZE_H;
          end if;
        end if;

      when ST_FILL =>
        if in_i.valid = '1' and data_in_s.ack.ready = '1' then
          rin.idle_left <= idle_count_c-1;
          rin.count <= r.count + 1;
          rin.last <= in_i.last;
          if in_i.last = '1' or r.count = 2**max_txn_length_l2_c - 2 then
            rin.state <= ST_SIZE_H;
          end if;
        elsif in_i.valid = '0' and data_in_s.ack.ready = '1' then
          if r.idle_left /= 0 then
            rin.idle_left <= r.idle_left-1;
          else
            rin.state <= ST_SIZE_H;
          end if;
        end if;

      when ST_SIZE_H =>
        if out_i.ready = '1' then
          rin.state <= ST_SIZE_L;
        end if;

      when ST_SIZE_L =>
        if out_i.ready = '1' then
          rin.state <= ST_FLUSH;
        end if;

      when ST_FLUSH =>
        if out_i.ready = '1' and data_out_s.req.valid = '1' then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= ST_EMPTY;
          end if;
        end if;
    end case;
  end process;

  fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => 2**max_txn_length_l2_c,
      data_width_c => 8,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      out_data_o => data_out_s.req.data,
      out_ready_i => data_out_s.ack.ready,
      out_valid_o => data_out_s.req.valid,

      in_data_i => data_in_s.req.data,
      in_valid_i => data_in_s.req.valid,
      in_ready_o => data_in_s.ack.ready
      );

  mux: process(in_i, out_i, r, data_in_s, data_out_s, count_s)
  begin
    out_o <= pipe_req_idle_c;
    data_in_s.req <= pipe_req_idle_c;
    in_o <= framed_accept(false);
    data_out_s.ack <= pipe_ack_idle_c;

    case r.state is
      when ST_RESET =>
        null;

      when ST_EMPTY | ST_FILL =>
        data_in_s.req <= pipe_flit(in_i.data, in_i.valid = '1');
        in_o <= framed_accept(data_in_s.ack.ready = '1');

      when ST_SIZE_H =>
        out_o <= pipe_flit('0' & r.last & std_ulogic_vector(count_s(13 downto 8)));

      when ST_SIZE_L =>
        out_o <= pipe_flit(std_ulogic_vector(count_s(7 downto 0)));

      when ST_FLUSH =>
        out_o <= data_out_s.req;
        data_out_s.ack <= out_i;
    end case;
  end process;

end architecture;
