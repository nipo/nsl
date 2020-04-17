library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, signalling, nsl_coresight;

package dp is
  constant DP_CMD_RUN           : std_ulogic_vector(7 downto 0):= "0-------";
  constant DP_CMD_RUN_0         : std_ulogic_vector(7 downto 0):= "00------";
  constant DP_CMD_RUN_1         : std_ulogic_vector(7 downto 0):= "01------";
  constant DP_CMD_TURNAROUND    : std_ulogic_vector(7 downto 0):= "110100--";
  constant DP_CMD_ABORT         : std_ulogic_vector(7 downto 0):= "11000000";
  constant DP_CMD_DIVISOR       : std_ulogic_vector(7 downto 0):= "11000001";
  constant DP_CMD_BITBANG       : std_ulogic_vector(7 downto 0):= "111-----";
  constant DP_CMD_RW            : std_ulogic_vector(7 downto 0):= "10------";
  constant DP_CMD_W             : std_ulogic_vector(7 downto 0):= "10-0----";
  constant DP_CMD_R             : std_ulogic_vector(7 downto 0):= "10-1----";
  constant DP_CMD_AP_READ       : std_ulogic_vector(7 downto 0):= "1011----";
  constant DP_CMD_AP_WRITE      : std_ulogic_vector(7 downto 0):= "1010----";
  constant DP_CMD_DP_READ       : std_ulogic_vector(7 downto 0):= "1001----";
  constant DP_CMD_DP_WRITE      : std_ulogic_vector(7 downto 0):= "1000----";

  constant DP_RSP_ACK          : std_ulogic_vector(7 downto 0):= "-----001";
  constant DP_RSP_WAIT         : std_ulogic_vector(7 downto 0):= "-----010";
  constant DP_RSP_ERROR        : std_ulogic_vector(7 downto 0):= "-----100";
  constant DP_RSP_PAR_OK       : std_ulogic_vector(7 downto 0):= "----0---";
  constant DP_RSP_PAR_ERROR    : std_ulogic_vector(7 downto 0):= "----1---";
  
  type dp_cmd_data is record
    data : std_ulogic_vector(31 downto 0);
    op   : std_ulogic_vector(7 downto 0);
  end record;

  type dp_rsp_data is record
    data   : std_ulogic_vector(31 downto 0);
    ack    : std_ulogic_vector(2 downto 0);
    par_ok : std_ulogic;
  end record;

  component dp_framed_swdp
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_val   : in nsl_bnoc.framed.framed_req;
      p_cmd_ack   : out nsl_bnoc.framed.framed_ack;

      p_rsp_val   : out nsl_bnoc.framed.framed_req;
      p_rsp_ack   : in nsl_bnoc.framed.framed_ack;

      p_swd_o     : out nsl_coresight.swd.swd_master_o;
      p_swd_i     : in  nsl_coresight.swd.swd_master_i
      );
  end component;

  component dp_transactor
    port (
      p_clk      : in  std_ulogic;
      p_resetn   : in  std_ulogic;

      p_cmd_val  : in  std_ulogic;
      p_cmd_ack  : out std_ulogic;
      p_cmd_data : in  dp_cmd_data;

      p_rsp_val  : out std_ulogic;
      p_rsp_ack  : in  std_ulogic;
      p_rsp_data : out dp_rsp_data;

      p_swd_o    : out nsl_coresight.swd.swd_master_o;
      p_swd_i    : in  nsl_coresight.swd.swd_master_i
      );
  end component;

  component swdp is
    generic(
      idr : unsigned(31 downto 0) := X"0ba00477"
      );
    port(
      swd_i : in nsl_coresight.swd.swd_slave_i;
      swd_o : out nsl_coresight.swd.swd_slave_o;
      
      dap_i : in nsl_coresight.dapbus.dapbus_m_i;
      dap_o : out nsl_coresight.dapbus.dapbus_m_o;

      ctrl_o : out std_ulogic_vector(31 downto 0);
      stat_i : in std_ulogic_vector(31 downto 0);

      abort_o : out std_ulogic_vector(4 downto 0)
      );
  end component;

end dp;
