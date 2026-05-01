library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity axi4_stream_sized_from_framed is
  generic(
    in_config_c      : config_t;
    out_config_c     : config_t;
    max_txn_length_c : natural := 2048
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture rtl of axi4_stream_sized_from_framed is

  constant pipe_config_c : config_t := config(bytes => in_config_c.data_width, last => true);
  
  signal fifo_in_ms : master_t;
  signal fifo_in_ss : slave_t;
  signal fifo_out_ms : master_t;
  signal fifo_out_ss : slave_t;

  type state_t is (
    STATE_RESET,
    STATE_DATA,
    STATE_SIZE_L,
    STATE_SIZE_H,
    STATE_DATA_FLUSH
    );

  type regs_t is record
    state: state_t;
    count: unsigned(15 downto 0);
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i, fifo_in_ss, fifo_out_ms) is
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_DATA;
        rin.count <= (others => '1');

      when STATE_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(pipe_config_c, fifo_in_ss) then
          rin.count <= r.count + 1;
          if is_last(in_config_c, in_i) then
            rin.state <= STATE_SIZE_L;
          end if;
        end if;

      when STATE_SIZE_L =>
        if is_ready(out_config_c, out_i) then
          rin.state <= STATE_SIZE_H;
        end if;

      when STATE_SIZE_H =>
        if is_ready(out_config_c, out_i) then
          rin.state <= STATE_DATA_FLUSH;
        end if;

      when STATE_DATA_FLUSH =>
        if is_ready(out_config_c, out_i) and is_valid(pipe_config_c, fifo_out_ms) then
          rin.count <= r.count - 1;
          if r.count = 0 then
            rin.state <= STATE_DATA;
          end if;
        end if;
    end case;
  end process;

  data_fifo: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => pipe_config_c,
      depth_c => max_txn_length_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      in_i => fifo_in_ms,
      in_o => fifo_in_ss,
      in_free_o => open,

      out_o => fifo_out_ms,
      out_i => fifo_out_ss,
      out_available_o => open
      );

  mealy: process(r, in_i, out_i, fifo_in_ss, fifo_out_ms) is
  begin
    out_o <= transfer_defaults(out_config_c);
    fifo_in_ms <= transfer_defaults(pipe_config_c);
    in_o <= accept(in_config_c, false);
    fifo_out_ss <= accept(pipe_config_c, false);

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_DATA =>
        fifo_in_ms <= transfer(pipe_config_c,
                             bytes => bytes(in_config_c, in_i),
                             valid => is_valid(in_config_c, in_i),
                             last  => is_last(in_config_c, in_i));
        in_o <= accept(in_config_c, is_ready(pipe_config_c, fifo_in_ss));

      when STATE_SIZE_L =>
        out_o <= transfer(out_config_c,
                         bytes => from_suv(std_ulogic_vector(r.count(7 downto 0))),
                         valid => true);

      when STATE_SIZE_H =>
        out_o <= transfer(out_config_c,
                         bytes => from_suv(std_ulogic_vector(r.count(15 downto 8))),
                         valid => true);

      when STATE_DATA_FLUSH =>
        out_o <= fifo_out_ms;
        fifo_out_ss <= out_i;
    end case;
  end process;

end architecture;
