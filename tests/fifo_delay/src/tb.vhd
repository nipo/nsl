library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library util, nsl, testing;

architecture arch of tb is

  constant width : integer := 8;
  constant latency : integer := 2;

  type fifo_t is
  record
    valid : std_ulogic;
    ready : std_ulogic;
    data : std_ulogic_vector(width-1 downto 0);
  end record;

  signal s_delay_in, s_delayed, s_stabilized, s_out : fifo_t;

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

begin

  reset_sync_clk: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_clk,
      p_clk => s_clk
      );

  gen: testing.fifo.fifo_file_reader
    generic map(
      width => width,
      filename => "input.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_valid => s_delay_in.valid,
      p_ready => s_delay_in.ready,
      p_data => s_delay_in.data,
      p_done => s_done(0)
      );

  delay_writer: nsl.fifo.fifo_delayed_writer
    generic map(
      width => width,
      latency => latency
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_in_data => s_delay_in.data,
      p_in_ready => s_delay_in.ready,
      p_in_valid => s_delay_in.valid,

      p_out_data => s_delayed.data,
      p_out_ready_delayed => s_delayed.ready,
      p_out_valid => s_delayed.valid
      );

  delay: testing.fifo.fifo_delay
    generic map(
      width => width,
      latency => latency
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_in_data => s_delayed.data,
      p_in_ready => s_delayed.ready,
      p_in_valid => s_delayed.valid,

      p_out_data => s_stabilized.data,
      p_out_ready => s_stabilized.ready,
      p_out_valid => s_stabilized.valid
      );

  stabilizer: nsl.fifo.fifo_input_stabilized
    generic map(
      width => width,
      latency => latency
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_in_data => s_stabilized.data,
      p_in_ready => s_stabilized.ready,
      p_in_valid => s_stabilized.valid,

      p_out_data => s_out.data,
      p_out_ready => s_out.ready,
      p_out_valid => s_out.valid
      );

  check: testing.fifo.fifo_file_checker
    generic map(
      width => width,
      filename => "output.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_ready => s_out.ready,
      p_valid => s_out.valid,
      p_data => s_out.data,
      p_done => s_done(1)
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 13 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
