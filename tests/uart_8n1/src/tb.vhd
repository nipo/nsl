library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
library testing;
use testing.fifo.all;
use nsl.uart.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(1 downto 0) := (others => '0');

  signal s_uart : std_ulogic;
  signal s_accept : std_ulogic;
  signal s_data_valid : std_ulogic_vector(1 downto 0);
  subtype word_t is std_ulogic_vector(7 downto 0);
  type word_array is array (natural range <>) of word_t;
  signal s_data : word_array(0 to 1);

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  u_in: nsl.uart.uart_8n1_tx
    generic map(
      p_clk_rate => 100000000,
      baud_rate => 1000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_data => s_data(0),
      p_data_val => s_data_valid(0),
      p_ready => s_accept,
      p_uart_tx => s_uart
      );

  u_out: nsl.uart.uart_8n1_rx
    generic map(
      p_clk_rate => 100000000,
      baud_rate => 1000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_data => s_data(1),
      p_data_val => s_data_valid(1),
      p_uart_rx => s_uart
      );

  gen: testing.fifo.fifo_counter_generator
    generic map(
      width => 8
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_empty_n => s_data_valid(0),
      p_read => s_accept,
      p_data => s_data(0)
      );

  check: testing.fifo.fifo_counter_checker
    generic map(
      width => 8
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_full_n => open,
      p_write => s_data_valid(1),
      p_data => s_data(1)
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait for 1 ms;
    s_done <= (others => '1');
    wait;
  end process;
  
  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
