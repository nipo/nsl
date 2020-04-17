library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

package clockfree is

  component clockfree_slave is
    port (
      reset_n_i : in  std_ulogic := '1';
      clock_o   : out std_ulogic;

      slave_address_c : in unsigned(7 downto 1);

      i2c_o : out nsl_i2c.i2c.i2c_o;
      i2c_i : in  nsl_i2c.i2c.i2c_i;

      start_o    : out std_ulogic;
      stop_o     : out std_ulogic;
      selected_o : out std_ulogic;

      error_i : in std_ulogic := '0';

      read_data_i   : in  std_ulogic_vector(7 downto 0);
      read_strobe_o : out std_ulogic;
      read_ready_i  : in  std_ulogic := '1';

      write_data_o   : out std_ulogic_vector(7 downto 0);
      write_strobe_o : out std_ulogic;
      write_ready_i  : in  std_ulogic := '1'
      );
  end component;

  component clockfree_memory_controller is
    generic (
      addr_bytes_c : integer range 1 to 4 := 2;
      data_bytes_c : integer range 1 to 4 := 1
      );
    port (
      clock_o : out std_ulogic;

      slave_address_c : in unsigned(7 downto 1);

      i2c_o : out nsl_i2c.i2c.i2c_o;
      i2c_i : in  nsl_i2c.i2c.i2c_i;

      start_o    : out std_ulogic;
      stop_o     : out std_ulogic;
      selected_o : out std_ulogic;

      addr_o : out unsigned(addr_bytes_c*8-1 downto 0);

      read_strobe_o : out std_ulogic;
      read_data_i   : in  std_ulogic_vector(data_bytes_c*8-1 downto 0);
      read_ready_i  : in  std_ulogic := '1';

      write_strobe_o : out std_ulogic;
      write_data_o   : out std_ulogic_vector(data_bytes_c*8-1 downto 0);
      write_ready_i  : in  std_ulogic := '1'
      );
  end component;

  component clockfree_memory is
    generic (
      address: unsigned(7 downto 1);
      addr_width: integer range 1 to 16 := 8;
      granularity: integer range 1 to 4 := 1
      );
    port (
      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i
      );
  end component;

  subtype control_word_32 is std_ulogic_vector(31 downto 0);
  type control_word_32_vector is array(natural range <>) of control_word_32;

  component clockfree_control_bank is
    generic (
      control_count_c: natural range 0 to 64 := 0;
      status_count_c: natural range 0 to 64 := 0
      );
    port (
      slave_address_c: unsigned(7 downto 1);

      i2c_o: out nsl_i2c.i2c.i2c_o;
      i2c_i: in  nsl_i2c.i2c.i2c_i;
      i2c_irq_n_o : out std_ulogic;

      control_o: out control_word_32;
      control_write_o: out std_ulogic_vector(0 to control_count_c-1);
      status_i: in control_word_32_vector(0 to status_count_c-1);

      -- asynchronous
      raise_irq_i : in std_ulogic := '0'
      );
  end component;
  
end package clockfree;
