library work, ieee;
use ieee.std_logic_1164.all;
use work.usb_commands.all;

entity tb is
end tb;

architecture sim of tb is

  signal clk_60mhz      : std_logic;
  signal usb_dn         : std_logic := 'L';
  signal usb_dp         : std_logic := 'Z';
  signal reset_n_sync     : std_logic := '1';
  signal rst_neg_ext    : std_logic;

BEGIN

  p_clk_60mhz : process
  begin
    clk_60mhz <= '0';

    wait for 2 ns;

    while true loop
      clk_60mhz <= '0';
      wait for 8000 ps;
      clk_60mhz <= '1';
      wait for 8667 ps;
    end loop;
  end process;

  usb_fs_master : entity work.usb_fs_master
    port map(
      rst_neg_ext => rst_neg_ext,
      usb_dp      => usb_dp,
      usb_dn      => usb_dn
      );

  reset_n_sync_drive: process
  begin
    reset_n_sync <= '0';
    wait for 10 us;
    reset_n_sync <= '1';
    wait;
  end process;
  
  usb_fs_slave : entity work.dut
    generic map(
      clock_rate_mhz => 48
      )
    port map(
      reset_n_i       => rst_neg_ext,
      d_p_io          => usb_dp,
      d_n_io          => usb_dn
      );

end sim;
