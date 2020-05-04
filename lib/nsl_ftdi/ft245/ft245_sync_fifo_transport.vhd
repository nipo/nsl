library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi;

entity ft245_sync_fifo_transport is
  port (
    slave_o : out nsl_ftdi.ft245.ft245_sync_fifo_slave_i;
    slave_i : in nsl_ftdi.ft245.ft245_sync_fifo_slave_o;
    master_o : out nsl_ftdi.ft245.ft245_sync_fifo_master_i;
    master_i : in nsl_ftdi.ft245.ft245_sync_fifo_master_o
    );
end ft245_sync_fifo_transport;

architecture arch of ft245_sync_fifo_transport is

  signal oes : std_ulogic_vector(0 to 1);
  signal data : std_ulogic_vector(7 downto 0);
  
begin

  oes(0) <= master_i.data_oe;
  oes(1) <= master_i.oe after 3 ns;

  assert
    oes /= "11"
    report "Write conflict on FT245 data bus"
    severity failure;

  with oes select data <=
    (others => '-') when "00",
    slave_i.data when "01",
    master_i.data when "10",
    (others => 'X') when others;

  slave_o.data <= data after 3 ns;
  slave_o.rd <= master_i.rd after 3 ns;
  slave_o.wr <= master_i.wr after 3 ns;
  master_o.clk <= slave_i.clk;
  master_o.data <= data after 3 ns;
  master_o.rxf <= slave_i.rxf after 3 ns;
  master_o.txe <= slave_i.txe after 3 ns;
  
end architecture;
