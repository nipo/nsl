library ieee;
use ieee.std_logic_1164.all;

library nsl;
library util;

entity ftdi_fs_slave is
  port (
    p_clk    : out std_ulogic;
    p_resetn : in  std_ulogic;

    p_fsclk    : in  std_ulogic;
    p_fsdo     : out std_logic;
    p_fsdi     : in  std_ulogic;
    p_fscts    : out std_ulogic;

    p_in_ready   : in  std_ulogic;
    p_in_valid   : out std_ulogic;
    p_in_data    : out std_ulogic_vector(7 downto 0);
    p_in_channel : out std_ulogic;

    p_out_ready   : out std_ulogic;
    p_out_valid   : in  std_ulogic;
    p_out_data    : in  std_ulogic_vector(7 downto 0);
    p_out_channel : in  std_ulogic
    );
end ftdi_fs_slave;

architecture arch of ftdi_fs_slave is

  signal s_resetn : std_ulogic;
  
begin

  p_clk <= p_fsclk;

  rsync: util.sync.sync_rising_edge
    port map(
      p_in => p_resetn,
      p_out => s_resetn,
      p_clk => p_fsclk
      );
  
  tx: nsl.ftdi.ftdi_fs_tx
    port map(
      p_clk => p_fsclk,
      p_resetn => s_resetn,
      
      p_clk_en => '1',
      p_serial => p_fsdo,
      p_cts => '1',

      p_ready => p_out_ready,
      p_valid => p_out_valid,
      p_data => p_out_data,
      p_channel => p_out_channel
      );

  rx: nsl.ftdi.ftdi_fs_rx
    port map(
      p_clk => p_fsclk,
      p_resetn => s_resetn,

      p_clk_en => open,
      p_serial => p_fsdi,
      p_cts => p_fscts,

      p_ready => p_in_ready,
      p_valid => p_in_valid,
      p_data => p_in_data,
      p_channel => p_in_channel
      );
  
end arch;
