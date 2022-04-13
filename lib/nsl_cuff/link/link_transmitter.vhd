library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_data;
use nsl_line_coding.ibm_8b10b.all;
use nsl_cuff.protocol.all;
use nsl_cuff.lane.all;
use nsl_cuff.link.all;
use nsl_data.bytestream.all;
  
entity link_transmitter is
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
end entity;

architecture beh of link_transmitter is

  signal state_s: lane_state_t;
  
begin

  with state_i select state_s <=
    LANE_BIT_ALIGN when LINK_LANE_ALIGN,
    LANE_BUS_ALIGN when LINK_BUS_ALIGN,
    LANE_BUS_ALIGN_READY when LINK_READY,
    LANE_DATA when LINK_STARTUP,
    LANE_DATA when LINK_RUNNING;
  
  lanes: for i in 0 to lane_count_c-1
  generate
    lane: nsl_cuff.lane.lane_transmitter
      generic map(
        lane_count_c => lane_count_c,
        lane_index_c => i,
        mtu_l2_c => mtu_l2_c,
        ibm_8b10b_implementation_c => ibm_8b10b_implementation_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        data_i => data_i(i),
        lane_o => lane_o(i),

        state_i => state_s
        );
  end generate;
  
end architecture;
