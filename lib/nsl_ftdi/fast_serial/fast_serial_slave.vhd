library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;
library nsl_clocking;

entity fast_serial_slave is
  port (
    clock_o    : out std_ulogic;
    reset_n_i : in  std_ulogic;

    fs_clk_i    : in  std_ulogic;
    fs_do_o     : out std_logic;
    fs_di_i     : in  std_ulogic;
    fs_cts_o    : out std_ulogic;

    in_ready_i   : in  std_ulogic;
    in_valid_o   : out std_ulogic;
    in_data_o    : out std_ulogic_vector(7 downto 0);
    in_channel_o : out std_ulogic;

    out_ready_o   : out std_ulogic;
    out_valid_i   : in  std_ulogic;
    out_data_i    : in  std_ulogic_vector(7 downto 0);
    out_channel_i : in  std_ulogic
    );
end fast_serial_slave;

architecture arch of fast_serial_slave is

  signal s_resetn : std_ulogic;
  
begin

  clock_o <= fs_clk_i;

  rsync: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_i,
      data_o => s_resetn,
      clock_o => fs_clk_i
      );
  
  tx: nsl_ftdi.fast_serial.fast_serial_tx
    port map(
      clock_o => fs_clk_i,
      reset_n_i => s_resetn,
      
      clock_en_i => '1',
      serial_o => fs_do_o,
      cts_i => '1',

      ready_o => out_ready_o,
      valid_i => out_valid_i,
      data_i => out_data_i,
      channel_i => out_channel_i
      );

  rx: nsl_ftdi.fast_serial.fast_serial_rx
    port map(
      clock_o => fs_clk_i,
      reset_n_i => s_resetn,

      clock_en_o => open,
      serial_i => fs_di_i,
      cts_o => fs_cts_o,

      ready_i => in_ready_i,
      valid_o => in_valid_o,
      data_o => in_data_o,
      channel_o => in_channel_o
      );
  
end arch;
