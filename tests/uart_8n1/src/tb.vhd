library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
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
  signal s_data_valid : std_ulogic;
  signal s_data : std_ulogic_vector(7 downto 0);

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  io: nsl.uart.uart_8n1_tx
    generic map(
      p_clk_rate => 100000000,
      baud_rate => 1000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_data => s_data,
      p_data_val => s_data_valid,
      p_ready => s_accept,
      p_uart_tx => s_uart
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_data_valid <= '0';
    s_resetn_async <= '1';
    wait for 100 ns;
    wait until falling_edge(s_clk);
    s_data <= x"12";
    s_data_valid <= '1';
    wait until falling_edge(s_accept);
    wait until falling_edge(s_clk);
    s_data <= x"35";
    wait until falling_edge(s_accept);
    wait until falling_edge(s_clk);
    s_done(1) <= '1';
    wait;
  end process;
  
  s_done(0) <= s_accept;

  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
