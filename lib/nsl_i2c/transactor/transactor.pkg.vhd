library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_bnoc, nsl_data;

-- I2C bys master transactor that takes command stream from a framed interface.
package transactor is

  -- CMD: [READ | n-1]
  -- RSP: [Data * n]
  constant I2C_CMD_READ      : nsl_bnoc.framed.framed_data_t := "1-------";
  constant I2C_CMD_READ_ACK  : nsl_bnoc.framed.framed_data_t := "11------";
  constant I2C_CMD_READ_NACK : nsl_bnoc.framed.framed_data_t := "10------";
  -- CMD: [WRITE | n-1, Data * n]
  -- RSP: [Ack * n]
  constant I2C_CMD_WRITE     : nsl_bnoc.framed.framed_data_t := "01------";
  -- CMD: [DIV | n-1]
  -- RSP: [00]
  constant I2C_CMD_DIV       : nsl_bnoc.framed.framed_data_t := "000-----";
  -- CMD: [START]
  -- RSP: [00 or ff]
  constant I2C_CMD_START     : nsl_bnoc.framed.framed_data_t := "00100000";
  -- CMD: [STOP]
  -- RSP: [00 or ff]
  constant I2C_CMD_STOP      : nsl_bnoc.framed.framed_data_t := "00100001";

  component transactor_framed_controller
    generic(
      clock_i_hz_c : natural
      );
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

  component framed_addressed_controller
    generic(
      addr_byte_count_c : natural;
      big_endian_c : boolean;
      txn_byte_count_max_c : positive
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      cmd_i  : in nsl_bnoc.framed.framed_ack;
      cmd_o  : out nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack;
      rsp_i  : in nsl_bnoc.framed.framed_req;

      valid_i : in std_ulogic;
      ready_o : out std_ulogic;
      saddr_i : in unsigned(7 downto 1);
      addr_i : in unsigned(8 * addr_byte_count_c - 1 downto 0) := (others => '0');
      write_i : in std_ulogic;
      wdata_i : in nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
      data_byte_count_i : in natural range 1 to txn_byte_count_max_c;

      valid_o : out std_ulogic;
      ready_i : in std_ulogic;
      rdata_o : out nsl_data.bytestream.byte_string(0 to txn_byte_count_max_c-1);
      error_o : out std_ulogic
      );
  end component;
  
end package transactor;
