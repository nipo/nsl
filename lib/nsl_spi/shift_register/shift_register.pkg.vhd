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

  component fifo_shift_register
    generic(
      divisor_max_c : natural := 0;
      width_c : natural := 8;
      msb_first_c : boolean := true
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      divisor_i : in integer range 0 to divisor_max_c := divisor_max_c;
      cpol_i : in std_ulogic := '0';
      cpha_i : in std_ulogic := '0';
      
      data_i : in std_ulogic_vector(width_c-1 downto 0);
      valid_i : in std_ulogic;
      ready_o : out std_ulogic;

      data_o : out std_ulogic_vector(width_c-1 downto 0);
      valid_o : out std_ulogic;
      ready_i : in std_ulogic := '1';

      sd_o : out std_ulogic;
      sck_o : out std_ulogic;
      sd_i : in std_ulogic
      );
  end component;

end package shift_register;
