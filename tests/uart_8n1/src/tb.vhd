library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_clocking, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  constant parity : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_EVEN;
  constant width : natural := 8;

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 downto 0) := (others => '0');

  signal s_uart : std_ulogic;
  signal s_data_valid : std_ulogic_vector(1 downto 0);
  signal s_data_ready : std_ulogic_vector(1 downto 0);
  subtype word_t is std_ulogic_vector(width - 1 downto 0);
  type word_array is array (natural range <>) of word_t;
  signal s_data : word_array(0 to 1);

begin

  reset_sync_clk0: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(0),
      clock_i => s_clk(0)
      );

  reset_sync_clk1: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(1),
      clock_i => s_clk(1)
      );

  u_in: nsl_uart.serdes.uart_tx
    generic map(
      divisor_width => 6,
      bit_count_c => width,
      stop_count_c => 1,
      parity_c => parity
      )
    port map(
      reset_n_i => s_resetn_clk(0),
      clock_i => s_clk(0),

      divisor_i => "100000",
    
      data_i => s_data(0),
      valid_i => s_data_valid(0),
      ready_o => s_data_ready(0),

      uart_o => s_uart
      );

  u_out: nsl_uart.serdes.uart_rx
    generic map(
      divisor_width => 6,
      bit_count_c => width,
      stop_count_c => 1,
      parity_c => parity
      )
    port map(
      reset_n_i => s_resetn_clk(1),
      clock_i => s_clk(1),

      divisor_i => "010111",

      data_o => s_data(1),
      valid_o => s_data_valid(1),
      ready_i => s_data_ready(1),

      uart_i => s_uart
      );

  gen: nsl_simulation.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_clk(0),
      clock_i => s_clk(0),
      valid_o => s_data_valid(0),
      ready_i => s_data_ready(0),
      data_o => s_data(0)
      );

  check: nsl_simulation.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_clk(1),
      clock_i => s_clk(1),
      ready_o => s_data_ready(1),
      valid_i => s_data_valid(1),
      data_i => s_data(1)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 7 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o => s_clk,
      done_i => s_done
      );

  process
  begin
    wait for 1 ms;
    s_done <= (others => '1');
    wait;
  end process;

end;
