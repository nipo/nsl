library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.ti.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(1 downto 0) := (others => '0');
  signal s_easyscale : std_ulogic;

  signal s_dev_addr : std_ulogic_vector(7 downto 0);
  signal s_ack_req  : std_ulogic;
  signal s_reg_addr : std_ulogic_vector(1 downto 0);
  signal s_data     : std_ulogic_vector(4 downto 0);
  signal s_start    : std_ulogic;
  signal s_busy     : std_ulogic;
  signal s_dev_ack  : std_ulogic;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  es: nsl.ti.ti_easyscale
    generic map(
      p_clk_hz => 100000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_easyscale => s_easyscale,
      p_dev_addr => s_dev_addr,
      p_ack_req => s_ack_req,
      p_reg_addr => s_reg_addr,
      p_data => s_data,
      p_start => s_start,
      p_busy => s_busy,
      p_dev_ack => s_dev_ack
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_start <= '0';
    s_resetn_async <= '1';
    wait for 100 ns;
    s_dev_addr <= x"12";
    s_ack_req <= '1';
    s_reg_addr <= "01";
    s_data <= "01011";
    s_start <= '1';
    wait for 20 ns;
    s_start <= '0';
    wait until falling_edge(s_busy);
    s_done(1) <= '1';
    wait for 20 ns;
    wait;
  end process;

  s_done(0) <= not s_busy;
  
  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
