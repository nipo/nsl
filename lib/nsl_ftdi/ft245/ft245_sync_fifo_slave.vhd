library ieee;
use ieee.std_logic_1164.all;

entity ft245_sync_fifo_slave is
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
end ft245_sync_fifo_slave;

architecture arch of ft245_sync_fifo_slave is
  
begin
  
  ftdi_clk_o <= clock_i;
  in_data_o <= std_ulogic_vector(ftdi_data_io);
  ftdi_data_io <= std_logic_vector(out_data_i) when ftdi_oe_n_i = '0' else (others => 'Z');  
  ftdi_rxf_n_o <= not out_valid_i;
  ftdi_txe_n_o <= not in_ready_i;
  out_ready_o <= not ftdi_rd_n_i;
  in_valid_o <= not ftdi_wr_n_i;

end arch;
