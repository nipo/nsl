library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;

entity committed_sizer is
  generic(
    clock_count_c : natural range 1 to 2 := 1;
    offset_c : integer := 0;
    txn_count_c : natural;
    max_size_l2_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);
    
    in_i   : in committed_req;
    in_o   : out committed_ack;

    size_o : out unsigned(max_size_l2_c-1 downto 0);
    size_valid_o : out std_ulogic;
    size_ready_i : in std_ulogic;

    out_o   : out committed_req;
    out_i   : in committed_ack
    );
end entity;

architecture beh of committed_sizer is

  type state_t is (
    ST_RESET,
    ST_COUNT,
    ST_REPORT
    );

  type regs_t is
  record
    count: unsigned(max_size_l2_c-1 downto 0);
    state: state_t;
  end record;

  signal r, rin: regs_t;

  signal size_valid_s, size_ready_s : std_ulogic;
  signal fifo_in_s : committed_bus;

begin

  regs: process(clock_i(0), reset_n_i) is
  begin
    if rising_edge(clock_i(0)) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, fifo_in_s.ack, size_ready_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_COUNT;
        rin.count <= to_unsigned(offset_c, rin.count'length);

      when ST_COUNT =>
        if in_i.valid = '1' and fifo_in_s.ack.ready = '1' then
          if in_i.last = '1' then
            rin.state <= ST_REPORT;
          else
            rin.count <= r.count + 1;
          end if;
        end if;

      when ST_REPORT =>
        if size_ready_s = '1' then
          rin.state <= ST_COUNT;
          rin.count <= to_unsigned(offset_c, rin.count'length);
        end if;
    end case;
  end process;

  mealy: process(r, in_i, fifo_in_s.ack) is
  begin
    in_o.ready <= fifo_in_s.ack.ready;
    fifo_in_s.req <= in_i;

    case r.state is
      when ST_RESET =>
        in_o.ready <= '0';
        fifo_in_s.req.valid <= '0';
        size_valid_s <= '0';

      when ST_COUNT =>
        size_valid_s <= '0';

      when ST_REPORT =>
        in_o.ready <= '0';
        fifo_in_s.req.valid <= '0';
        size_valid_s <= '1';
    end case;
  end process;
  
  data_pipe: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => 2**max_size_l2_c,
      data_width_c => 9,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_data_i(8) => fifo_in_s.req.last,
      in_data_i(7 downto 0) => fifo_in_s.req.data,
      in_valid_i => fifo_in_s.req.valid,
      in_ready_o => fifo_in_s.ack.ready,

      out_data_o(8) => out_o.last,
      out_data_o(7 downto 0) => out_o.data,
      out_ready_i => out_i.ready,
      out_valid_o => out_o.valid
      );

  size_pipe: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => txn_count_c,
      data_width_c => max_size_l2_c,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_data_i => std_ulogic_vector(r.count),
      in_valid_i => size_valid_s,
      in_ready_o => size_ready_s,

      unsigned(out_data_o) => size_o,
      out_ready_i => size_ready_i,
      out_valid_o => size_valid_o
      );

end architecture;
