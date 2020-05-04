library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

entity ft245_sync_fifo_slave is
  port (
    clock_i    : in std_ulogic;

    bus_i : in nsl_ftdi.ft245.ft245_sync_fifo_slave_i;
    bus_o : out nsl_ftdi.ft245.ft245_sync_fifo_slave_o;

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
  
  bus_o.clk <= clock_i;
  bus_o.data <= out_data_i;
  bus_o.rxf <= out_valid_i;
  bus_o.txe <= in_ready_i;
  
  in_data_o <= bus_i.data;
  out_ready_o <= bus_i.rd;
  in_valid_o <= bus_i.wr;

end arch;
