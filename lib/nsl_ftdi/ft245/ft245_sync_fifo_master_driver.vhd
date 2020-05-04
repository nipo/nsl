library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

entity ft245_sync_fifo_master_driver is
  port (
    bus_o : out nsl_ftdi.ft245.ft245_sync_fifo_master_i;
    bus_i : in nsl_ftdi.ft245.ft245_sync_fifo_master_o;

    ft245_clk_i   : in    std_ulogic;
    ft245_data_io : inout std_logic_vector(7 downto 0);
    ft245_rxf_n_i : in    std_ulogic;
    ft245_txe_n_i : in    std_ulogic;
    ft245_rd_n_o  : out   std_ulogic;
    ft245_wr_n_o  : out   std_ulogic;
    ft245_oe_n_o  : out   std_ulogic
    );
end ft245_sync_fifo_master_driver;

architecture arch of ft245_sync_fifo_master_driver is
begin

  bus_o.clk <= ft245_clk_i;
  bus_o.data <= std_ulogic_vector(ft245_data_io);
  bus_o.rxf <= not ft245_rxf_n_i;
  bus_o.txe <= not ft245_txe_n_i;
  ft245_data_io <= std_logic_vector(bus_i.data)
                   when bus_i.data_oe = '1'
                   else (others => 'Z');
  ft245_rd_n_o <= not bus_i.rd;
  ft245_wr_n_o <= not bus_i.wr;
  ft245_oe_n_o <= not bus_i.oe;
  
end arch;
