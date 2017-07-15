library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

package swd is

  constant SWDP_CMD_AP_RUN       : std_ulogic_vector(7 downto 0):= "11------"; -- cycles - 1
  constant SWDP_CMD_AP_SEL       : std_ulogic_vector(7 downto 0):= "1001----";
  constant SWDP_CMD_DP_BANK      : std_ulogic_vector(7 downto 0):= "1000----";  
  constant SWDP_CMD_ABORT        : std_ulogic_vector(7 downto 0):= "1010----"; -- ---- TBD
  -- constant SWDP_CMD_          : std_ulogic_vector(7 downto 0):= "101100--";
  constant SWDP_CMD_WAKEUP       : std_ulogic_vector(7 downto 0):= "10110000";
  constant SWDP_CMD_DP_REG_WRITE : std_ulogic_vector(7 downto 0):= "101101--";
  constant SWDP_CMD_DP_REG_READ  : std_ulogic_vector(7 downto 0):= "101110--";
  constant SWDP_CMD_RESET        : std_ulogic_vector(7 downto 0):= "1011110-"; -- SRST value
  constant SWDP_CMD_JTAG_CONFIG  : std_ulogic_vector(7 downto 0):= "10111110"; -- IR pre/post, DR pre/post, Target
  constant SWDP_CMD_AP_READ      : std_ulogic_vector(7 downto 0):= "00------";
  constant SWDP_CMD_AP_WRITE     : std_ulogic_vector(7 downto 0):= "01------";
  
  constant SWDP_RSP_AP_READ_DONE : std_ulogic_vector(7 downto 0):= "0001----";
  constant SWDP_RSP_AP_WRITE_DONE: std_ulogic_vector(7 downto 0):= "0000----";
  constant SWDP_RSP_DP_READ_DONE : std_ulogic_vector(7 downto 0):= "0011----";
  constant SWDP_RSP_DP_WRITE_DONE: std_ulogic_vector(7 downto 0):= "0010----";
  constant SWDP_RSP_MGMT_DONE    : std_ulogic_vector(7 downto 0):= "0100----";
  constant SWDP_RSP_RESET_DONE   : std_ulogic_vector(7 downto 0):= "0101----";
  constant SWDP_RSP_UNHANDLED    : std_ulogic_vector(7 downto 0):= "1000----";
  constant SWDP_RSP_ACK          : std_ulogic_vector(7 downto 0):= "-----001";
  constant SWDP_RSP_WAIT         : std_ulogic_vector(7 downto 0):= "-----010";
  constant SWDP_RSP_ERROR        : std_ulogic_vector(7 downto 0):= "-----100";
  constant SWDP_RSP_PAR_OK       : std_ulogic_vector(7 downto 0):= "----0---";
  constant SWDP_RSP_PAR_ERROR    : std_ulogic_vector(7 downto 0):= "----1---";

  constant SWD_CMD_TURNAROUND    : std_ulogic_vector(2 downto 0):= "1--";
  constant SWD_CMD_CONST         : std_ulogic_vector(2 downto 0):= "000";
  constant SWD_CMD_BITBANG       : std_ulogic_vector(2 downto 0):= "001";
  constant SWD_CMD_READ          : std_ulogic_vector(2 downto 0):= "011";
  constant SWD_CMD_WRITE         : std_ulogic_vector(2 downto 0):= "010";
  
  type swd_cmd_data is record
    data : std_ulogic_vector(31 downto 0);
    op   : std_ulogic_vector(2 downto 0);
    ap   : std_ulogic;
    addr : unsigned(1 downto 0);
  end record;

  type swd_rsp_data is record
    data   : std_ulogic_vector(31 downto 0);
    ack    : std_ulogic_vector(2 downto 0);
    par_ok : std_ulogic;
  end record;
  
  component swd_master is
    port(
      p_clk      : in  std_ulogic;
      p_resetn   : in  std_ulogic;

      p_clk_div  : in  unsigned(15 downto 0);

      p_cmd_val  : in  std_ulogic;
      p_cmd_ack  : out std_ulogic;
      p_cmd_data : in  swd_cmd_data;

      p_rsp_val  : out std_ulogic;
      p_rsp_ack  : in  std_ulogic;
      p_rsp_data : out swd_rsp_data;
      
      p_swclk    : out std_ulogic;
      p_swdio_i  : in  std_ulogic;
      p_swdio_o  : out std_ulogic;
      p_swdio_oe : out std_ulogic
      );
  end component;

  component swd_swdp is
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_srst     : out std_ulogic;

      p_cmd_val  : in fifo_framed_cmd;
      p_cmd_ack  : out fifo_framed_rsp;

      p_rsp_val  : out fifo_framed_cmd;
      p_rsp_ack  : in fifo_framed_rsp;

      p_swclk    : out std_ulogic;
      p_swdio_i  : in  std_ulogic;
      p_swdio_o  : out std_ulogic;
      p_swdio_oe : out std_ulogic
      );
  end component; 

end swd;
