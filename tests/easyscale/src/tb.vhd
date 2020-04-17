library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_ti, nsl_clocking, nsl_io;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(1 downto 0) := (others => '0');
  signal s_easyscale : std_ulogic;
  signal s_easyscale_o : nsl_io.io.tristated;
  signal s_easyscale_i : std_ulogic;

  signal s_dev_addr : std_ulogic_vector(7 downto 0);
  signal s_ack_req  : std_ulogic;
  signal s_reg_addr : std_ulogic_vector(1 downto 0);
  signal s_data     : std_ulogic_vector(4 downto 0);
  signal s_start    : std_ulogic;
  signal s_busy     : std_ulogic;
  signal s_dev_ack  : std_ulogic;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  driver: nsl_io.io.tristated_io_driver
    port map(
      v_i => s_easyscale_o,
      v_o => s_easyscale_i,
      io_io => s_easyscale
      );

  es: nsl_ti.easyscale.easyscale_master
    generic map(
      clock_rate_c => 100000000
      )
    port map(
      reset_n_i => s_resetn_clk,
      clock_i => s_clk,
      easyscale_o => s_easyscale_o,
      easyscale_i => s_easyscale_i,
      dev_addr_i => s_dev_addr,
      ack_req_i => s_ack_req,
      reg_addr_i => s_reg_addr,
      data_i => s_data,
      start_i => s_start,
      busy_o => s_busy,
      dev_ack_o => s_dev_ack
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
    wait for 200 ns;
    s_done(1) <= '1';
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
