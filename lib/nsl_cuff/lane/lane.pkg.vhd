library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding;
use nsl_cuff.protocol.all;

package lane is

  type lane_state_t is (
    LANE_BIT_ALIGN,
    LANE_BUS_ALIGN,
    LANE_BUS_ALIGN_READY,
    LANE_DATA
    );
  
  component lane_transmitter is
    generic(
      lane_index_c : natural;
      lane_count_c : natural;
      mtu_l2_c : natural range 0 to 15;
      ibm_8b10b_implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in cuff_data_t;
      lane_o : out cuff_code_word_t;

      state_i: in lane_state_t
      );
  end component;

  component lane_receiver is
    generic(
      lane_index_c : natural;
      lane_count_c : natural;
      mtu_l2_c : natural range 0 to 15;
      ibm_8b10b_implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      lane_i : in cuff_code_word_t;
      data_o : out cuff_data_t;

      align_restart_o : out std_ulogic;
      align_valid_o : out std_ulogic;
      align_ready_i : in std_ulogic;

      sync_sof_o, sync_eof_o: out std_ulogic;

      state_o: out lane_state_t
      );
  end component;
      
end package lane;
