library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_data;
use nsl_cuff.protocol.all;
use nsl_data.bytestream.all;

package link is

  type link_state_t is (
    LINK_LANE_ALIGN,
    LINK_BUS_ALIGN,
    LINK_READY,
    LINK_STARTUP,
    LINK_RUNNING
    );
  
  component link_transmitter is
    generic(
      lane_count_c : natural;
      mtu_l2_c : natural range 0 to 15;
      ibm_8b10b_implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in cuff_data_vector(0 to lane_count_c-1);

      lane_o : out cuff_code_vector(0 to lane_count_c-1);
      state_i: in link_state_t
      );
  end component;

  component link_receiver is
    generic(
      lane_count_c : natural;
      mtu_l2_c : natural range 0 to 15;
      ibm_8b10b_implementation_c : string := "logic"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From/to transceiver
      lane_i : in cuff_code_vector(0 to lane_count_c-1);
      align_restart_o : out std_ulogic;
      align_valid_o : out std_ulogic_vector(0 to lane_count_c-1);
      align_ready_i : in std_ulogic_vector(0 to lane_count_c-1);

      data_o : out cuff_data_vector(0 to lane_count_c-1);

      state_o: out link_state_t
      );
  end component;
  
      
end package link;
