library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi;

package shift_register is

  component spi_shift_register
    generic(
      width_c : natural;
      msb_first_c : boolean := true
      );
    port(
      spi_i       : in nsl_spi.spi.spi_slave_i;
      spi_o       : out nsl_spi.spi.spi_slave_o;

      tx_data_i   : in  std_ulogic_vector(width_c - 1 downto 0);
      tx_strobe_o : out std_ulogic;
      rx_data_o   : out std_ulogic_vector(width_c - 1 downto 0);
      rx_strobe_o : out std_ulogic
      );
  end component;

end package shift_register;
