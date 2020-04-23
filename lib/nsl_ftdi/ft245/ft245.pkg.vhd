library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ft245 is
  
  component ft245_sync_fifo_master
    generic (
      burst_length: integer := 64
      );
    port (
      clock_o    : out std_ulogic;
      reset_n_i  : in  std_ulogic;

      ftdi_clk_i  : in std_ulogic;
      ftdi_data_io : inout std_logic_vector(7 downto 0);
      ftdi_rxf_n_i : in std_ulogic;
      ftdi_txe_n_i : in std_ulogic;
      ftdi_rd_n_o  : out std_ulogic;
      ftdi_wr_n_o  : out std_ulogic;
      ftdi_oe_n_o  : out std_ulogic;

      in_ready_i : in  std_ulogic;
      in_valid_o : out std_ulogic;
      in_data_o  : out std_ulogic_vector(7 downto 0);

      out_ready_o : out std_ulogic;
      out_valid_i : in  std_ulogic;
      out_data_i  : in  std_ulogic_vector(7 downto 0)
      );
  end component;

  component ft245_sync_fifo_slave
    port (
      clock_i    : in std_ulogic;

      ftdi_clk_o  : out std_ulogic;
      ftdi_data_io : inout std_logic_vector(7 downto 0);
      ftdi_rxf_n_o : out std_ulogic;
      ftdi_txe_n_o : out std_ulogic;
      ftdi_rd_n_i  : in std_ulogic;
      ftdi_wr_n_i  : in std_ulogic;
      ftdi_oe_n_i  : in std_ulogic;

      in_ready_i : in  std_ulogic;
      in_valid_o : out std_ulogic;
      in_data_o  : out std_ulogic_vector(7 downto 0);

      out_ready_o : out std_ulogic;
      out_valid_i : in  std_ulogic;
      out_data_i  : in  std_ulogic_vector(7 downto 0)
      );
  end component;

end package ft245;
