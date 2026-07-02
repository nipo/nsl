library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_bnoc;

entity jtag_framed_transport_tap is
  generic(
    tx_fifo_depth_c : natural := 128;
    rx_fifo_depth_c : natural := 128
    );
  port(
    chip_tck_i : in std_ulogic := '0';
    chip_tms_i : in std_ulogic := '0';
    chip_tdi_i : in std_ulogic := '0';
    chip_tdo_o : out std_ulogic;

    -- Clocks the fifo, asynchronous to TCK of user reg
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;
    reset_n_o   : out std_ulogic;

    tx_i : in nsl_bnoc.framed.framed_req;
    tx_o : out nsl_bnoc.framed.framed_ack;

    rx_o : out nsl_bnoc.framed.framed_req;
    rx_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of jtag_framed_transport_tap is

begin

  inst: work.fifo_transport.jtag_fifo_transport_slave_tap
    generic map(
      width_c => 9,
      status_enable_c => true,
      rx_fifo_depth_c => rx_fifo_depth_c,
      tx_fifo_depth_c => tx_fifo_depth_c
      )
    port map(
      chip_tck_i => chip_tck_i,
      chip_tms_i => chip_tms_i,
      chip_tdi_i => chip_tdi_i,
      chip_tdo_o => chip_tdo_o,

      -- Clocks the fifo, asynchronous to TCK of user reg
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      reset_n_o => reset_n_o,

      tx_data_i(8) => tx_i.last,
      tx_data_i(7 downto 0) => tx_i.data,
      tx_valid_i => tx_i.valid,
      tx_ready_o => tx_o.ready,

      rx_data_o(8) => rx_o.last,
      rx_data_o(7 downto 0) => rx_o.data,
      rx_valid_o => rx_o.valid,
      rx_ready_i => rx_i.ready
      );
  
end architecture;
