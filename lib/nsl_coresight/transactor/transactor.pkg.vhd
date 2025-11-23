library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_coresight, nsl_io;

-- SW-DP master transactor. Can generate SWD operations with any
-- turnaround configuration.  Handle parity checking and bus error
-- conditions internally.
package transactor is

  constant DP_CMD_RUN           : std_ulogic_vector(7 downto 0):= "0-------";
  constant DP_CMD_RUN_0         : std_ulogic_vector(7 downto 0):= "00------";
  constant DP_CMD_RUN_1         : std_ulogic_vector(7 downto 0):= "01------";
  constant DP_CMD_TURNAROUND    : std_ulogic_vector(7 downto 0):= "110100--";
  constant DP_CMD_SYSTEM_RESET  : std_ulogic_vector(7 downto 0):= "1101100-";
  constant DP_CMD_ABORT         : std_ulogic_vector(7 downto 0):= "11000000";
  constant DP_CMD_DIVISOR       : std_ulogic_vector(7 downto 0):= "11000001";
  constant DP_CMD_BITBANG       : std_ulogic_vector(7 downto 0):= "111-----";
  constant DP_CMD_RW            : std_ulogic_vector(7 downto 0):= "10------";
  constant DP_CMD_W             : std_ulogic_vector(7 downto 0):= "10-0----";
  constant DP_CMD_R             : std_ulogic_vector(7 downto 0):= "10-1----";
  constant DP_CMD_AP_READ       : std_ulogic_vector(7 downto 0):= "1011----"; -- |
  constant DP_CMD_AP_WRITE      : std_ulogic_vector(7 downto 0):= "1010----"; -- | bits 3-2 are unused,
  constant DP_CMD_DP_READ       : std_ulogic_vector(7 downto 0):= "1001----"; -- | 1-0 is register name
  constant DP_CMD_DP_WRITE      : std_ulogic_vector(7 downto 0):= "1000----"; -- |

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

  component dp_framed_transactor
    port (
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      cmd_i : in  nsl_bnoc.framed.framed_req;
      cmd_o : out nsl_bnoc.framed.framed_ack;

      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in  nsl_bnoc.framed.framed_ack;

      swd_o : out nsl_coresight.swd.swd_master_o;
      swd_i : in  nsl_coresight.swd.swd_master_i;

      system_reset_n_o : out nsl_io.io.opendrain
      );
    --@-- grouped name:command, members:cmd;rsp
  end component;

  component dp_transactor
    port (
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      tick_i : in std_ulogic;
      
      cmd_valid_i : in  std_ulogic;
      cmd_ready_o : out std_ulogic;
      cmd_data_i  : in  dp_cmd_data;

      rsp_valid_o : out std_ulogic;
      rsp_ready_i : in  std_ulogic;
      rsp_data_o  : out dp_rsp_data;

      swd_o : out nsl_coresight.swd.swd_master_o;
      swd_i : in  nsl_coresight.swd.swd_master_i
      );
  end component;

end transactor;
