library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
library signalling;

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

      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i;

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

      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i;

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

      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i;

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
      address: unsigned(7 downto 1);
      addr_width: integer range 1 to 16 := 8;
      granularity: integer range 1 to 4 := 1
      );
    port (
      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i
      );
  end component;

  component i2c_slave_clkfree is
    port (
      p_resetn : in std_ulogic := '1';
      p_clk_out : out std_ulogic;

      address : in unsigned(7 downto 1);

      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i;

      p_start: out std_ulogic;
      p_stop: out std_ulogic;
      p_selected: out std_ulogic;

      p_error: in std_ulogic := '0';

      p_r_data: in std_ulogic_vector(7 downto 0);
      p_r_strobe: out std_ulogic;
      p_r_ready: in std_ulogic := '1';

      p_w_data: out std_ulogic_vector(7 downto 0);
      p_w_strobe: out std_ulogic;
      p_w_ready: in std_ulogic := '1'
      );
  end component;

  component i2c_slave_clocked is
    generic (
      clock_freq_c : natural := 100000000
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      address_i : in unsigned(7 downto 1);

      i2c_o  : out signalling.i2c.i2c_o;
      i2c_i  : in  signalling.i2c.i2c_i;

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

  component i2c_mem_clocked is
    generic (
      address: unsigned(7 downto 1);
      addr_width: integer range 1 to 16 := 8;
      granularity: integer range 1 to 4 := 1
      );
    port (
      reset_n_i : in std_ulogic := '1';
      clock_i : in std_ulogic;

      i2c_o  : out signalling.i2c.i2c_o;
      i2c_i  : in  signalling.i2c.i2c_i
      );
  end component;

  component i2c_mem_ctrl is
    generic (
      addr_bytes: integer range 1 to 4 := 2;
      data_bytes: integer range 1 to 4 := 1
      );
    port (
      p_clk : out std_ulogic;

      slave_address: in unsigned(7 downto 1);

      p_i2c_o  : out signalling.i2c.i2c_o;
      p_i2c_i  : in  signalling.i2c.i2c_i;

      p_start    : out std_ulogic;
      p_stop     : out std_ulogic;
      p_selected : out std_ulogic;

      p_addr     : out unsigned(addr_bytes*8-1 downto 0);

      p_r_strobe : out std_ulogic;
      p_r_data   : in  std_ulogic_vector(data_bytes*8-1 downto 0);
      p_r_ready  : in  std_ulogic := '1';

      p_w_strobe : out std_ulogic;
      p_w_data   : out std_ulogic_vector(data_bytes*8-1 downto 0);
      p_w_ready  : in  std_ulogic := '1'
      );
  end component;

  component i2c_mem_ctrl_clocked is
    generic (
      addr_bytes: integer range 1 to 4 := 2;
      data_bytes: integer range 1 to 4 := 1
      );
    port (
      reset_n_i : in std_ulogic := '1';
      clock_i : in std_ulogic;

      slave_address_i : in unsigned(7 downto 1);

      i2c_o  : out signalling.i2c.i2c_o;
      i2c_i  : in  signalling.i2c.i2c_i;

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

  subtype control_word_32 is std_ulogic_vector(31 downto 0);
  type control_word_32_vector is array(natural range <>) of control_word_32;

  component i2c_control_bank is
    generic (
      control_count: natural range 0 to 32 := 0;
      status_count: natural range 0 to 32 := 0
      );
    port (
      slave_address: in unsigned(7 downto 1);

      p_i2c_o: out signalling.i2c.i2c_o;
      p_i2c_i: in  signalling.i2c.i2c_i;
      p_i2c_irqn : out std_ulogic;

      p_control: out control_word_32;
      p_control_write: out std_ulogic_vector(0 to control_count-1);
      p_status: in control_word_32_vector(0 to status_count-1);
      -- asynchronous
      p_raise_irq : in std_ulogic := '0'
      );
  end component;
  
end package i2c;
