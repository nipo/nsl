library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;

package i2c is

  constant I2C_CMD_READ      : nsl.framed.framed_data_t := "1-------";
  constant I2C_CMD_READ_ACK  : nsl.framed.framed_data_t := "11------";
  constant I2C_CMD_READ_NACK : nsl.framed.framed_data_t := "10------";
  constant I2C_CMD_WRITE     : nsl.framed.framed_data_t := "01------";
  constant I2C_CMD_DIV       : nsl.framed.framed_data_t := "000-----";
  constant I2C_CMD_START     : nsl.framed.framed_data_t := "00100000";
  constant I2C_CMD_STOP      : nsl.framed.framed_data_t := "00100001";

  component i2c_framed_ctrl
    port(
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_scl       : in  std_ulogic;
      p_scl_drain : out std_ulogic; -- active high drain control
      p_sda       : in  std_ulogic;
      p_sda_drain : out std_ulogic; -- active high drain control

      p_cmd_val   : in nsl.framed.framed_req;
      p_cmd_ack   : out nsl.framed.framed_ack;
      p_rsp_val  : out nsl.framed.framed_req;
      p_rsp_ack  : in nsl.framed.framed_ack
      );
  end component;

  type i2c_cmd_t is (
    I2C_NOOP,
    I2C_START,
    I2C_STOP,
    I2C_WRITE,
    I2C_READ
    );
  
  component i2c_master
    generic(
      divisor_width : natural
      );
    port(
      p_clk    : in std_ulogic;
      p_resetn : in std_ulogic;

      p_divisor  : in std_ulogic_vector(divisor_width-1 downto 0);

      p_scl       : in  std_ulogic;
      p_scl_drain : out std_ulogic; -- active high drain control
      p_sda       : in  std_ulogic;
      p_sda_drain : out std_ulogic; -- active high drain control

      p_rack     : in  std_ulogic;
      p_rdata    : out std_ulogic_vector(7 downto 0);
      p_wack     : out std_ulogic;
      p_wdata    : in  std_ulogic_vector(7 downto 0);

      p_cmd      : in  i2c_cmd_t;
      p_busy     : out std_ulogic;
      p_done     : out std_ulogic
      );
  end component;

  component i2c_slave is
    port (
      p_clk: in std_ulogic;
      p_resetn: in std_ulogic;

      p_scl: in std_ulogic;
      p_sda: in std_ulogic;
      p_scl_drain: out std_ulogic;
      p_sda_drain: out std_ulogic;

      p_start: out std_ulogic;
      p_stop: out std_ulogic;

      p_rdata: in std_ulogic_vector(7 downto 0);
      p_read: out std_ulogic;

      p_wdata: out std_ulogic_vector(7 downto 0);
      p_wack: in std_ulogic;
      p_addr: out std_ulogic;
      p_write: out std_ulogic
      );
  end component;

  component i2c_mem is
    generic (
      slave_addr: std_ulogic_vector(6 downto 0);
      mem_addr_width: integer range 1 to 16 := 8
      );
    port (
      p_clk: in std_ulogic;
      p_resetn: in std_ulogic;
      p_scl: in std_ulogic;
      p_sda: in std_ulogic;
      p_scl_drain: out std_ulogic;
      p_sda_drain: out std_ulogic
      );
  end component;

end package i2c;