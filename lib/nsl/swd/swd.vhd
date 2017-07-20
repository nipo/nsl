library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

package swd is
  constant SWD_AP_INTERVAL     : std_ulogic_vector(7 downto 0):= "10------";
  constant SWD_AP_SEL_HIGH     : std_ulogic_vector(7 downto 0):= "1100----";
  constant SWD_AP_SEL_LOW      : std_ulogic_vector(7 downto 0):= "1101----";
  constant SWD_AP_TARGET_ADDR  : std_ulogic_vector(7 downto 0):= "1110----";
  constant SWD_AP_ABORT        : std_ulogic_vector(7 downto 0):= "1111----";
  constant SWD_AP_RW           : std_ulogic_vector(7 downto 0):= "0-------";
  constant SWD_AP_READ         : std_ulogic_vector(7 downto 0):= "00------";
  constant SWD_AP_WRITE        : std_ulogic_vector(7 downto 0):= "01------";
  
  constant SWD_DP_RUN           : std_ulogic_vector(7 downto 0):= "0-------";
  constant SWD_DP_RUN_0         : std_ulogic_vector(7 downto 0):= "00------";
  constant SWD_DP_RUN_1         : std_ulogic_vector(7 downto 0):= "01------";
  constant SWD_DP_TURNAROUND    : std_ulogic_vector(7 downto 0):= "110100--";
  -- Warning: Ensure DP_ABORT(4) = '0'
  constant SWD_DP_AP_ABORT      : std_ulogic_vector(7 downto 0):= "1100----";
  constant SWD_DP_BITBANG       : std_ulogic_vector(7 downto 0):= "111-----";
  constant SWD_DP_RW            : std_ulogic_vector(7 downto 0):= "10------";
  constant SWD_DP_W             : std_ulogic_vector(7 downto 0):= "10-0----";
  constant SWD_DP_R             : std_ulogic_vector(7 downto 0):= "10-1----";
  constant SWD_DP_AP_READ       : std_ulogic_vector(7 downto 0):= "1011----";
  constant SWD_DP_AP_WRITE      : std_ulogic_vector(7 downto 0):= "1010----";
  constant SWD_DP_DP_READ       : std_ulogic_vector(7 downto 0):= "1001----";
  constant SWD_DP_DP_WRITE      : std_ulogic_vector(7 downto 0):= "1000----";

  constant SWD_RSP_ACK          : std_ulogic_vector(7 downto 0):= "-----001";
  constant SWD_RSP_WAIT         : std_ulogic_vector(7 downto 0):= "-----010";
  constant SWD_RSP_ERROR        : std_ulogic_vector(7 downto 0):= "-----100";
  constant SWD_RSP_PAR_OK       : std_ulogic_vector(7 downto 0):= "----0---";
  constant SWD_RSP_PAR_ERROR    : std_ulogic_vector(7 downto 0):= "----1---";
  
  type swd_cmd_data is record
    data : std_ulogic_vector(31 downto 0);
    op   : std_ulogic_vector(7 downto 0);
  end record;

  type swd_rsp_data is record
    data   : std_ulogic_vector(31 downto 0);
    ack    : std_ulogic_vector(2 downto 0);
    par_ok : std_ulogic;
  end record;

  component swd_framed_dp
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_clk_div  : in  unsigned(15 downto 0);

      p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
      p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;

      p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
      p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

      p_swclk    : out std_logic;
      p_swdio_i  : in  std_logic;
      p_swdio_o  : out std_logic;
      p_swdio_oe : out std_logic
      );
  end component;

  component swd_dp
    port (
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

  component swd_framed_ap
    generic(
      srcid : nsl.fifo.component_id
      );
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
      p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;
      p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
      p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

      p_dp_cmd_val   : in nsl.fifo.fifo_framed_cmd;
      p_dp_cmd_ack   : out nsl.fifo.fifo_framed_rsp;
      p_dp_rsp_val   : out nsl.fifo.fifo_framed_cmd;
      p_dp_rsp_ack   : in nsl.fifo.fifo_framed_rsp
      );
  end component;

end swd;
