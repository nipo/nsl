library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.ioext.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(1 downto 0) := (others => '0');
  signal s_sr_d : std_ulogic;
  signal s_sr_clk : std_ulogic;
  signal s_sr_strobe : std_ulogic;

  signal s_data : std_ulogic_vector(7 downto 0);

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  io: nsl.ioext.ioext_sync_output
    generic map(
      p_clk_rate => 100000000,
      p_sr_clk_rate => 10000000
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_data => s_data,
      p_sr_d => s_sr_d,
      p_sr_strobe => s_sr_strobe,
      p_sr_clk => s_sr_clk,
      p_done => s_done(0)
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait for 100 ns;
    s_data <= x"12";
    wait for 20 ns;
    s_data <= x"12";
    wait for 200 ns;
    s_data <= x"34";
    s_done(1) <= '1';
    wait;
  end process;
  
  clock_gen: process(s_clk)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
