library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

package clocked is

  component clocked_slave is
    generic (
      clock_freq_c : natural := 100000000
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      address_i : in unsigned(7 downto 1);

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      start_o: out std_ulogic;
      stop_o: out std_ulogic;
      selected_o: out std_ulogic;

      error_i: in std_ulogic := '0';

      r_data_i: in std_ulogic_vector(7 downto 0);
      r_ready_o: out std_ulogic;
      r_valid_i: in std_ulogic := '1';

      w_data_o: out std_ulogic_vector(7 downto 0);
      w_valid_o: out std_ulogic;
      w_ready_i: in std_ulogic := '1'
      );
  end component;

  component clocked_memory_controller is
    generic (
      addr_bytes: integer range 1 to 4 := 2;
      data_bytes: integer range 1 to 4 := 1
      );
    port (
      reset_n_i : in std_ulogic := '1';
      clock_i : in std_ulogic;

      slave_address_i : in unsigned(7 downto 1);

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      start_o    : out std_ulogic;
      stop_o     : out std_ulogic;
      selected_o : out std_ulogic;

      addr_o     : out unsigned(addr_bytes*8-1 downto 0);

      r_ready_o  : out std_ulogic;
      r_data_i   : in  std_ulogic_vector(data_bytes*8-1 downto 0);
      r_valid_i  : in  std_ulogic := '1';

      w_valid_o  : out std_ulogic;
      w_data_o   : out std_ulogic_vector(data_bytes*8-1 downto 0);
      w_ready_i  : in  std_ulogic := '1'
      );
  end component;

  component clocked_memory is
    generic (
      address: unsigned(7 downto 1);
      addr_width: integer range 1 to 16 := 8;
      granularity: integer range 1 to 4 := 1
      );
    port (
      reset_n_i : in std_ulogic := '1';
      clock_i : in std_ulogic;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i
      );
  end component;
  
end package clocked;
