library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fast_serial is

  component fast_serial_master
    port (
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      fs_clk_o    : out std_ulogic;
      fs_clk_en_o : out std_ulogic;
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
  end component;

  component fast_serial_slave
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
  end component;

  component fast_serial_tx
    port (
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      clock_en_i  : in  std_ulogic;
      serial_o  : out std_ulogic;
      cts_i     : in  std_ulogic;

      ready_o   : out std_ulogic;
      valid_i   : in  std_ulogic;
      data_i    : in  std_ulogic_vector(7 downto 0);
      channel_i : in  std_ulogic
      );
  end component;

  component fast_serial_rx
    port (
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      clock_en_o  : out std_ulogic;
      serial_i  : in  std_logic;
      cts_o     : out std_ulogic;

      ready_i   : in  std_ulogic;
      valid_o   : out std_ulogic;
      data_o    : out std_ulogic_vector(7 downto 0);
      channel_o : out std_ulogic
      );
  end component;

end package fast_serial;
