library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

entity fast_serial_master is
  port (
    clock_i    : in std_ulogic;
    reset_n_i : in std_ulogic;

    fs_clk_o    : out std_ulogic;
    fs_clk_o_en : out std_ulogic;
    fs_do_i     : in  std_logic;
    fs_di_o     : out std_ulogic;
    fs_cts_i    : in  std_ulogic;

    in_ready_i   : in  std_ulogic;
    in_valid_o   : out std_ulogic;
    in_data_o    : out std_ulogic_vector(7 downto 0);
    in_channel_o : out std_ulogic;

    out_ready_o   : out std_ulogic;
    out_valid_i   : in  std_ulogic;
    out_data_i    : in  std_ulogic_vector(7 downto 0);
    out_channel_i : in  std_ulogic
    );
end fast_serial_master;

architecture arch of fast_serial_master is

  signal fsclk_en : std_ulogic;

begin

  fs_clk_o_en <= fsclk_en;
  fs_clk_o <= clock_i;
  
  tx: nsl_ftdi.fast_serial.fast_serial_tx
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      
      clock_en_i => fsclk_en,
      serial_o => fs_di_o,
      cts_i => fs_cts_i,

      ready_o => out_ready_o,
      valid_i => out_valid_i,
      data_i => out_data_i,
      channel_i => out_channel_i
      );

  rx: nsl_ftdi.fast_serial.fast_serial_rx
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      clock_en_o => fsclk_en,
      serial_i => fs_do_i,
      cts_o => open,

      ready_i => in_ready_i,
      valid_o => in_valid_o,
      data_o => in_data_o,
      channel_o => in_channel_o
      );
  
end arch;
