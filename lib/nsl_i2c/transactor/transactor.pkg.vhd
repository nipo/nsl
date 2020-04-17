library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_bnoc;

package transactor is

  constant I2C_CMD_READ      : nsl_bnoc.framed.framed_data_t := "1-------";
  constant I2C_CMD_READ_ACK  : nsl_bnoc.framed.framed_data_t := "11------";
  constant I2C_CMD_READ_NACK : nsl_bnoc.framed.framed_data_t := "10------";
  constant I2C_CMD_WRITE     : nsl_bnoc.framed.framed_data_t := "01------";
  constant I2C_CMD_DIV       : nsl_bnoc.framed.framed_data_t := "000-----";
  constant I2C_CMD_START     : nsl_bnoc.framed.framed_data_t := "00100000";
  constant I2C_CMD_STOP      : nsl_bnoc.framed.framed_data_t := "00100001";

  component transactor_framed_controller
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;
      rsp_o  : out nsl_bnoc.framed.framed_req;
      rsp_i  : in nsl_bnoc.framed.framed_ack
      );
  end component;

  type i2c_cmd_t is (
    I2C_NOOP,
    I2C_START,
    I2C_STOP,
    I2C_WRITE,
    I2C_READ
    );
  
  component transactor_master
    generic(
      divisor_width : natural
      );
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      divisor_i  : in std_ulogic_vector(divisor_width-1 downto 0);

      i2c_o  : out nsl_i2c.i2c.i2c_o;
      i2c_i  : in  nsl_i2c.i2c.i2c_i;

      rack_i     : in  std_ulogic;
      rdata_o    : out std_ulogic_vector(7 downto 0);
      wack_o     : out std_ulogic;
      wdata_i    : in  std_ulogic_vector(7 downto 0);

      cmd_i      : in  i2c_cmd_t;
      busy_o     : out std_ulogic;
      done_o     : out std_ulogic
      );
  end component;
  
end package transactor;
