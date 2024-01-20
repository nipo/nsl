library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, work;

entity spi_framed_transport_master is
  port(
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    enable_i    : in std_ulogic := '1';
    div_i       : in unsigned(6 downto 0);
    cpol_i      : in std_ulogic := '0';
    cpha_i      : in std_ulogic := '0';
    cs_i        : in unsigned(2 downto 0);

    irq_n_i     : in std_ulogic := '0';

    tx_i : in  nsl_bnoc.framed.framed_req;
    tx_o : out nsl_bnoc.framed.framed_ack;
    rx_o : out nsl_bnoc.framed.framed_req;
    rx_i : in  nsl_bnoc.framed.framed_ack;

    cmd_o : out nsl_bnoc.framed.framed_req;
    cmd_i : in  nsl_bnoc.framed.framed_ack;
    rsp_i : in  nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of spi_framed_transport_master is

  signal txd, rxd: std_ulogic_vector(8 downto 0);
  
begin
  
  txd <= tx_i.last & tx_i.data;
  rx_o.data <= rxd(7 downto 0);
  rx_o.last <= rxd(8);

  t: work.fifo_transport.spi_fifo_transport_master
    generic map(
      width_c => txd'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      enable_i => enable_i,
      div_i => div_i,
      cpol_i => cpol_i,
      cpha_i => cpha_i,
      cs_i => cs_i,

      irq_n_i => irq_n_i,

      tx_data_i => txd,
      tx_valid_i => tx_i.valid,
      tx_ready_o => tx_o.ready,
      rx_data_o => rxd,
      rx_valid_o => rx_o.valid,
      rx_ready_i => rx_i.ready,
      
      cmd_o => cmd_o,
      cmd_i => cmd_i,
      rsp_i => rsp_i,
      rsp_o => rsp_o
      );

end architecture;
