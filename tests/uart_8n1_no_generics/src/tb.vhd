library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_clocking, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  constant n_data : natural := 50;
  constant width : natural := 8;

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 downto 0) := (others => '0');

  signal s_uart : std_ulogic;
  signal s_rtr  : std_ulogic;

  signal s_data_valid : std_ulogic_vector(1 downto 0);
  signal s_data_ready : std_ulogic_vector(1 downto 0);
  subtype word_t is std_ulogic_vector(width - 1 downto 0);
  type word_array is array (natural range <>) of word_t;
  signal s_data : word_array(0 to 1);

  signal s_rx_ready : std_ulogic := '1';
  
  signal s_parity      : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_EVEN;
  signal s_stop_count  : natural := 1;
  signal s_parity_u    : unsigned(1 downto 0);
  signal s_stop_count_u: unsigned(1 downto 0);
  signal s_rtr_active  : std_ulogic := '0';
  signal s_rx_handshake : std_ulogic;
begin

  s_rx_handshake <= s_data_valid(1) and s_rx_ready;

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

  s_parity_u <= to_unsigned(nsl_uart.serdes.parity_t'pos(s_parity), 2);
  s_stop_count_u <= to_unsigned(s_stop_count, 2);

  u_in: nsl_uart.serdes.uart_tx_no_generics
    generic map(
      bit_count_c => width
      )
    port map(
      reset_n_i => s_resetn_clk(0),
      clock_i => s_clk(0),

      divisor_i => "100000",
    
      data_i => s_data(0),
      valid_i => s_data_valid(0),
      ready_o => s_data_ready(0),

      uart_o => s_uart,
      rtr_i  => s_rtr,

      stop_count_i => s_stop_count_u,
      parity_i => s_parity_u,
      rtr_active_i => s_rtr_active
      );

  u_out: nsl_uart.serdes.uart_rx_no_generics
    generic map(
      bit_count_c => width
      )
    port map(
      reset_n_i => s_resetn_clk(1),
      clock_i => s_clk(1),

      divisor_i => "010111",

      data_o => s_data(1),
      valid_o => s_data_valid(1),
      ready_i => s_rx_ready, -- s_data_ready(1),

      uart_i => s_uart,
      rts_o  => s_rtr,
      
      stop_count_i => s_stop_count_u,
      parity_i => s_parity_u,
      rts_active_i => s_rtr_active
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
      valid_i => s_rx_handshake,
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
    s_rx_ready <= '1';
    wait until s_data_ready(1) = '1';
    
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;
    
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 1;
    s_parity <= nsl_uart.serdes.PARITY_ODD;

    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;


    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 1;
    s_parity <= nsl_uart.serdes.PARITY_NONE;

    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;

    -- Now try with RTR/RTS
        
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 1;
    s_parity <= nsl_uart.serdes.PARITY_EVEN;
    s_rtr_active <= '1';
        
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    s_rx_ready <= '0';
    wait for 30 us;
    s_rx_ready <= '1';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;

    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 1;
    s_parity <= nsl_uart.serdes.PARITY_ODD;

    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    s_rx_ready <= '0';
    wait for 30 us;
    s_rx_ready <= '1';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;


    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    s_rx_ready <= '0';
    wait for 30 us;
    s_rx_ready <= '1';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 1;
    s_parity <= nsl_uart.serdes.PARITY_NONE;

    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    s_rx_ready <= '0';
    wait for 30 us;
    s_rx_ready <= '1';
    wait until s_data_valid(1) = '1';
    s_stop_count <= 2;


    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    wait until s_data_valid(1) = '1';
    wait until s_data_valid(1) = '0';
    s_rx_ready <= '0';
    wait for 30 us;
    s_rx_ready <= '1';
    wait until s_data_valid(1) = '1';

    wait for 20 ns;
    s_done <= (others => '1');
    
    wait;
  end process;

end;
