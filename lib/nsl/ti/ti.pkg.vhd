library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.framed.all;

package ti is

  component ti_framed_easyscale is
    generic(
      p_clk_rate : natural
      );
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_easyscale: inout std_logic;

      p_cmd_val  : in  nsl.framed.framed_req;
      p_cmd_ack  : out nsl.framed.framed_ack;

      p_rsp_val : out nsl.framed.framed_req;
      p_rsp_ack : in  nsl.framed.framed_ack
      );
  end component;

  component ti_easyscale is
    generic(
      p_clk_rate : natural range 1000000 to 100000000
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_easyscale: inout std_logic;

      p_dev_addr : in std_ulogic_vector(7 downto 0);
      p_ack_req  : in std_ulogic;
      p_reg_addr : in std_ulogic_vector(1 downto 0);
      p_data     : in std_ulogic_vector(4 downto 0);
      p_start    : in std_ulogic;

      p_busy     : out std_ulogic;
      p_dev_ack  : out std_ulogic
      );
  end component;

  constant TI_CC_CMD_CMD       : framed_data_t := "000-----";
  constant TI_CC_CMD_ACQUIRE   : framed_data_t := "00100000";
  constant TI_CC_CMD_RESET     : framed_data_t := "00100001";
  constant TI_CC_CMD_WAIT      : framed_data_t := "01------";
  constant TI_CC_CMD_DIV       : framed_data_t := "11------";
  
  component ti_framed_cc is
    generic(
      divisor_shift : natural := 0
      );
    port(
      p_resetn    : in  std_ulogic;
      p_clk       : in  std_ulogic;

      p_cc_resetn : out std_ulogic;
      p_cc_dc     : out std_ulogic;
      p_cc_ddo    : out std_ulogic;
      p_cc_ddi    : in  std_ulogic;
      p_cc_ddoe   : out std_ulogic;

      p_cmd_val   : in nsl.framed.framed_req;
      p_cmd_ack   : out nsl.framed.framed_ack;

      p_rsp_val  : out nsl.framed.framed_req;
      p_rsp_ack  : in nsl.framed.framed_ack
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

  component ti_cc_master is
    generic(
      divisor_width : natural
      );
    port(
      p_resetn    : in  std_ulogic;
      p_clk       : in  std_ulogic;

      p_divisor  : in std_ulogic_vector(divisor_width-1 downto 0);

      p_cc_resetn : out std_ulogic;
      p_cc_dc     : out std_ulogic;
      p_cc_ddo    : out std_ulogic;
      p_cc_ddi    : in  std_ulogic;
      p_cc_ddoe   : out std_ulogic;

      p_ready    : out std_ulogic;
      p_rdata    : out std_ulogic_vector(7 downto 0);
      p_wdata    : in  std_ulogic_vector(7 downto 0);

      p_cmd      : in  cc_cmd_t;
      p_busy     : out std_ulogic;
      p_done     : out std_ulogic
      );
  end component;

end package ti;
