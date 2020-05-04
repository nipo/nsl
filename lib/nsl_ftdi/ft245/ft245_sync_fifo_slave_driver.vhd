library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

entity ft245_sync_fifo_slave_driver is
  port (
    bus_o : out nsl_ftdi.ft245.ft245_sync_fifo_slave_i;
    bus_i : in nsl_ftdi.ft245.ft245_sync_fifo_slave_o;

    ft245_clk_o   : out   std_ulogic;
    ft245_data_io : inout std_logic_vector(7 downto 0);
    ft245_rxf_n_o : out   std_ulogic;
    ft245_txe_n_o : out   std_ulogic;
    ft245_rd_n_i  : in    std_ulogic;
    ft245_wr_n_i  : in    std_ulogic;
    ft245_oe_n_i  : in    std_ulogic
    );
end ft245_sync_fifo_slave_driver;

architecture arch of ft245_sync_fifo_slave_driver is
begin

  ft245_clk_o <= bus_i.clk;
  ft245_data_io <= std_logic_vector(bus_i.data)
                   when ft245_oe_n_i = '0'
                   else (others => 'Z');
  ft245_rxf_n_o <= not bus_i.rxf;
  ft245_txe_n_o <= not bus_i.txe;
  bus_o.data <= std_ulogic_vector(ft245_data_io);
  bus_o.rd <= not ft245_rd_n_i;
  bus_o.wr <= not ft245_wr_n_i;

end arch;
