library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

package flow_control is

  component xonxoff_rx is
    generic(
      xoff_c: byte := x"13";
      xon_c: byte := x"11"
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      ready_o : out std_ulogic;
      
      serdes_data_i  : in byte;
      serdes_valid_i : in std_ulogic;
      serdes_ready_o : out std_ulogic

      rx_data_o      : out byte;
      rx_valid_o     : out std_ulogic;
      rx_ready_i     : in std_ulogic
      );
  end component;

  component xonxoff_tx is
    generic(
      xoff_c: byte := x"13";
      xon_c: byte := x"11"
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      ready_i     : in std_ulogic;

      tx_data_i  : in byte;
      tx_valid_i : in std_ulogic;
      tx_ready_o : out std_ulogic

      serdes_data_o      : out byte;
      serdes_valid_o     : out std_ulogic;
      serdes_ready_i     : in std_ulogic
      );
  end component;

end package ssp;
