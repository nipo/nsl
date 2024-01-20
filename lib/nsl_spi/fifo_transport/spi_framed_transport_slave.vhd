library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, work;

entity spi_framed_transport_slave is
  generic(
    cs_n_active_c : std_ulogic := '0'
    );
  port(
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    spi_i       : in  nsl_spi.spi.spi_slave_i;
    spi_o       : out nsl_spi.spi.spi_slave_o;
    irq_n_o     : out std_ulogic;

    cpol_i : in std_ulogic := '0';
    cpha_i : in std_ulogic := '0';

    tx_i : in  nsl_bnoc.framed.framed_req;
    tx_o : out nsl_bnoc.framed.framed_ack;
    rx_o : out nsl_bnoc.framed.framed_req;
    rx_i : in  nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of spi_framed_transport_slave is

  signal txd, rxd: std_ulogic_vector(8 downto 0);
  
begin
  
  txd <= tx_i.last & tx_i.data;
  rx_o.data <= rxd(7 downto 0);
  rx_o.last <= rxd(8);

  t: work.fifo_transport.spi_fifo_transport_slave
    generic map(
      width_c => rxd'length,
      cs_n_active_c => cs_n_active_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      spi_i => spi_i,
      spi_o => spi_o,
      irq_n_o => irq_n_o,
      
      cpol_i => cpol_i,
      cpha_i => cpha_i,

      tx_data_i => txd,
      tx_valid_i => tx_i.valid,
      tx_ready_o => tx_o.ready,
      rx_data_o => rxd,
      rx_valid_o => rx_o.valid,
      rx_ready_i => rx_i.ready
      );

end architecture;
