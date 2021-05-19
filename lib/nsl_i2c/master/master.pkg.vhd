library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;
use nsl_i2c.i2c."+";

package master is

  type i2c_bus_cmd_t is (
    I2C_BUS_START,
    I2C_BUS_STOP,
    I2C_BUS_BYTE
    );
  
  component master_clock_driver is
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      half_cycle_clock_count_i  : in unsigned;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      ready_o : out std_ulogic;
      valid_i : in std_ulogic;
      cmd_i : in i2c_bus_cmd_t;

      abort_i : in std_ulogic;
      failed_o : out std_ulogic;
      owned_o : out std_ulogic
      );
  end component;
  
  component master_shift_register is
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      -- Start detected on bus
      start_i : in std_ulogic;
      -- Arbitration lost
      -- Driver should deassert enable_i and wait subsequent start/stop
      arb_ok_o : out std_ulogic;

      -- Whether to drive the bus for next word cycle
      enable_i : in std_ulogic;
      -- Whether to send or receive data
      send_mode_i : in std_ulogic;

      -- If sending data:
      -- - driver puts a word through send fifo
      -- - driver retrieves ack through recv fifo / bit (0)
      -- If receiving data:
      -- - driver retrieves a word through recv fifo
      -- - driver puts ack through send fifo / bit (0)

      send_valid_i : in std_ulogic;
      send_ready_o : out std_ulogic;
      send_data_i : in std_ulogic_vector(7 downto 0);

      recv_valid_o : out std_ulogic;
      recv_ready_i : in std_ulogic;
      recv_data_o : out std_ulogic_vector(7 downto 0)
      );
  end component;

end package;
