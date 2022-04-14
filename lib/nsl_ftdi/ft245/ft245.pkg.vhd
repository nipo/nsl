library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- FT245-style "synchronous fifo" mode.
package ft245 is

  type ft245_sync_fifo_master_o is
  record
    data_oe : std_ulogic;
    data    : std_ulogic_vector(7 downto 0);
    rd      : std_ulogic;
    wr      : std_ulogic;
    oe      : std_ulogic;
  end record;

  type ft245_sync_fifo_master_i is
  record
    clk  : std_ulogic;
    data : std_ulogic_vector(7 downto 0);
    rxf  : std_ulogic;
    txe  : std_ulogic;
  end record;

  type ft245_sync_fifo_master_bus is
  record
    i : ft245_sync_fifo_master_i;
    o : ft245_sync_fifo_master_o;
  end record;
  
  type ft245_sync_fifo_slave_o is
  record
    clk  : std_ulogic;
    data : std_ulogic_vector(7 downto 0);
    rxf  : std_ulogic;
    txe  : std_ulogic;
  end record;

  type ft245_sync_fifo_slave_i is
  record
    data : std_ulogic_vector(7 downto 0);
    rd   : std_ulogic;
    wr   : std_ulogic;
  end record;

  type ft245_sync_fifo_slave_bus is
  record
    i : ft245_sync_fifo_slave_i;
    o : ft245_sync_fifo_slave_o;
  end record;

  component ft245_sync_fifo_transport
    port(
      slave_o : out ft245_sync_fifo_slave_i;
      slave_i : in ft245_sync_fifo_slave_o;
      master_o : out ft245_sync_fifo_master_i;
      master_i : in ft245_sync_fifo_master_o
      );
  end component;

  component ft245_sync_fifo_slave_driver
    port(
      bus_o : out ft245_sync_fifo_slave_i;
      bus_i : in ft245_sync_fifo_slave_o;

      ft245_clk_o   : out   std_ulogic;
      ft245_data_io : inout std_logic_vector(7 downto 0);
      ft245_rxf_n_o : out   std_ulogic;
      ft245_txe_n_o : out   std_ulogic;
      ft245_rd_n_i  : in    std_ulogic;
      ft245_wr_n_i  : in    std_ulogic;
      ft245_oe_n_i  : in    std_ulogic
      );
  end component;

  component ft245_sync_fifo_master_driver
    port(
      bus_o : out ft245_sync_fifo_master_i;
      bus_i : in ft245_sync_fifo_master_o;

      ft245_clk_i   : in    std_ulogic;
      ft245_data_io : inout std_logic_vector(7 downto 0);
      ft245_rxf_n_i : in    std_ulogic;
      ft245_txe_n_i : in    std_ulogic;
      ft245_rd_n_o  : out   std_ulogic;
      ft245_wr_n_o  : out   std_ulogic;
      ft245_oe_n_o  : out   std_ulogic
      );
  end component;
  
  component ft245_sync_fifo_master
    generic (
      burst_length: integer := 64
      );
    port (
      clock_o    : out std_ulogic;
      reset_n_i  : in  std_ulogic;

      bus_i : in ft245_sync_fifo_master_i;
      bus_o : out ft245_sync_fifo_master_o;

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

      bus_i : in ft245_sync_fifo_slave_i;
      bus_o : out ft245_sync_fifo_slave_o;

      in_ready_i : in  std_ulogic;
      in_valid_o : out std_ulogic;
      in_data_o  : out std_ulogic_vector(7 downto 0);

      out_ready_o : out std_ulogic;
      out_valid_i : in  std_ulogic;
      out_data_i  : in  std_ulogic_vector(7 downto 0)
      );
  end component;

end package ft245;
