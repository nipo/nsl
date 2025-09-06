library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

package pmod_i2s2 is

  component pmod_i2s2_driver is
    generic(
      line_in_slave_c: boolean := false
      );
    port(
      pmod_io: work.pmod.pmod_double_t;

      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      rx_sck_div_m1_i : in unsigned;
      rx_valid_o : out std_ulogic;
      rx_channel_o : out std_ulogic;
      rx_data_o  : out unsigned;

      tx_sck_div_m1_i : in unsigned;
      tx_ready_o : out std_ulogic;
      tx_channel_o : out std_ulogic;
      tx_data_i  : in unsigned
      );
  end component;

end package pmod_i2s2;
