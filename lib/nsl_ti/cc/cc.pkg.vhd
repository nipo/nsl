library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_io;

package cc is

  use nsl_bnoc.framed.framed_data_t;
  
  constant CC_CMD_CMD       : framed_data_t := "000-----";
  constant CC_CMD_ACQUIRE   : framed_data_t := "00100000";
  constant CC_CMD_RESET     : framed_data_t := "00100001";
  constant CC_CMD_WAIT      : framed_data_t := "01------";
  constant CC_CMD_DIV       : framed_data_t := "11------";

  type cc_m_o is
  record
    dc : std_ulogic;
    dd : nsl_io.io.directed;
    reset_n : std_ulogic;
  end record;

  type cc_m_i is
  record
    dd : std_ulogic;
  end record;
  
  component cc_framed_transactor is
    generic(
      divisor_shift : natural := 0
      );
    port(
      reset_n_i    : in  std_ulogic;
      clock_i       : in  std_ulogic;

      cc_o : out cc_m_o;
      cc_i : in cc_m_i;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;

      rsp_o  : out nsl_bnoc.framed.framed_req;
      rsp_i  : in nsl_bnoc.framed.framed_ack
      );
  end component;
  
  type cc_cmd_t is (
    CC_NOOP,
    CC_RESET_RELEASE,
    CC_RESET_ACQUIRE,
    CC_WAIT,
    CC_WRITE,
    CC_READ
    );

  component cc_master is
    generic(
      divisor_width : natural
      );
    port(
      reset_n_i    : in  std_ulogic;
      clock_i       : in  std_ulogic;

      divisor_i  : in std_ulogic_vector(divisor_width-1 downto 0);

      cc_o : out cc_m_o;
      cc_i : in cc_m_i;

      ready_o    : out std_ulogic;
      rdata_o    : out std_ulogic_vector(7 downto 0);
      wdata_i    : in  std_ulogic_vector(7 downto 0);

      cmd_i      : in  cc_cmd_t;
      busy_o     : out std_ulogic;
      done_o     : out std_ulogic
      );
  end component;

end package cc;
