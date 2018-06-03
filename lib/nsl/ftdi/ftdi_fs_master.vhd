library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity ftdi_fs_master is
  port (
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_fsclk    : out std_ulogic;
    p_fsclk_en : out std_ulogic;
    p_fsdo     : in  std_logic;
    p_fsdi     : out std_ulogic;
    p_fscts    : in  std_ulogic;

    p_in_ready   : in  std_ulogic;
    p_in_valid   : out std_ulogic;
    p_in_data    : out std_ulogic_vector(7 downto 0);
    p_in_channel : out std_ulogic;

    p_out_ready   : out std_ulogic;
    p_out_valid   : in  std_ulogic;
    p_out_data    : in  std_ulogic_vector(7 downto 0);
    p_out_channel : in  std_ulogic
    );
end ftdi_fs_master;

architecture arch of ftdi_fs_master is

  signal fsclk_en : std_ulogic;

begin

  p_fsclk_en <= fsclk_en;
  p_fsclk <= p_clk;
  
  tx: nsl.ftdi.ftdi_fs_tx
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      
      p_clk_en => fsclk_en,
      p_serial => p_fsdi,
      p_cts => p_fscts,

      p_ready => p_out_ready,
      p_valid => p_out_valid,
      p_data => p_out_data,
      p_channel => p_out_channel
      );

  rx: nsl.ftdi.ftdi_fs_rx
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,

      p_clk_en => fsclk_en,
      p_serial => p_fsdo,
      p_cts => open,

      p_ready => p_in_ready,
      p_valid => p_in_valid,
      p_data => p_in_data,
      p_channel => p_in_channel
      );
  
end arch;
