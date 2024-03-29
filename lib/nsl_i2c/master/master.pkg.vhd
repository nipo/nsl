library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;
use nsl_i2c.i2c."+";

-- I2C master implementation.
--
-- Master is split in two: A clock bus driver and a byte shifter.
--
-- - Clock driver is able to do bus management (start, stop) and clock
--   toggling.
--
-- - Shift register is able to exchange a byte and an acknowledge at a
--   time. As I2C is open drain, there is no difference between driving
--   0xff or NACK and reading.
--
-- A Master needs to instiantiate both blocks, a slave may be implemented only
-- with the latter and a bus monitor
package master is

  type i2c_bus_cmd_t is (
    I2C_BUS_RELEASE,
    I2C_BUS_START,
    I2C_BUS_HOLD,
    I2C_BUS_RUN,
    I2C_BUS_STOP
    );
  
  component master_clock_driver is
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      half_cycle_clock_count_i  : in unsigned;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      -- Accepted when ready_o is set
      cmd_i : in i2c_bus_cmd_t;

      ready_o : out std_ulogic;
      -- Only meaningful when ready_o is set
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
