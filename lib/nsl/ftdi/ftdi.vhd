library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ftdi is
  
  component ft245_sync_fifo_master
    generic (
      burst_length: integer := 64
      );
    port (
      p_clk    : out std_ulogic;
      p_resetn : in  std_ulogic;

      p_ftdi_clk  : in std_ulogic;
      p_ftdi_data : inout std_logic_vector(7 downto 0);
      p_ftdi_rxfn : in std_ulogic;
      p_ftdi_txen : in std_ulogic;
      p_ftdi_rdn  : out std_ulogic;
      p_ftdi_wrn  : out std_ulogic;
      p_ftdi_oen  : out std_ulogic;

      p_in_ready : in  std_ulogic;
      p_in_valid : out std_ulogic;
      p_in_data  : out std_ulogic_vector(7 downto 0);

      p_out_ready : out std_ulogic;
      p_out_valid : in  std_ulogic;
      p_out_data  : in  std_ulogic_vector(7 downto 0)
      );
  end component;

  component ft245_sync_fifo_slave
    port (
      p_clk    : in std_ulogic;

      p_ftdi_clk  : out std_ulogic;
      p_ftdi_data : inout std_logic_vector(7 downto 0);
      p_ftdi_rxfn : out std_ulogic;
      p_ftdi_txen : out std_ulogic;
      p_ftdi_rdn  : in std_ulogic;
      p_ftdi_wrn  : in std_ulogic;
      p_ftdi_oen  : in std_ulogic;

      p_in_ready : in  std_ulogic;
      p_in_valid : out std_ulogic;
      p_in_data  : out std_ulogic_vector(7 downto 0);

      p_out_ready : out std_ulogic;
      p_out_valid : in  std_ulogic;
      p_out_data  : in  std_ulogic_vector(7 downto 0)
      );
  end component;
  
  component ftdi_fs_master
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
  end component;

  component ftdi_fs_slave
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
  end component;

  component ftdi_fs_tx
    port (
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_clk_en  : in  std_ulogic;
      p_serial  : out std_ulogic;
      p_cts     : in  std_ulogic;

      p_ready   : out std_ulogic;
      p_valid   : in  std_ulogic;
      p_data    : in  std_ulogic_vector(7 downto 0);
      p_channel : in  std_ulogic
      );
  end component;

  component ftdi_fs_rx
    port (
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_clk_en  : out std_ulogic;
      p_serial  : in  std_logic;
      p_cts     : out std_ulogic;

      p_ready   : in  std_ulogic;
      p_valid   : out std_ulogic;
      p_data    : out std_ulogic_vector(7 downto 0);
      p_channel : out std_ulogic
      );
  end component;

end package ftdi;
