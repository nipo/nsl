library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_io;
use nsl_cuff.protocol.all;

package transceiver is
  
  component cuff_diff_transmitter is
    generic(
      lane_count_c : natural
      );
    port(
      clock_i : in std_ulogic;
      bit_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      lane_i : in cuff_code_vector(0 to lane_count_c-1);
      pad_o : out nsl_io.diff.diff_pair_vector(0 to lane_count_c-1)
      );
  end component;

  component cuff_diff_receiver is
    generic(
      lane_count_c : natural;
      input_fixed_delay_ps_c: natural := 0;
      has_input_alignment_c: boolean := true;
      diff_term : boolean := true
      );
    port(
      clock_i : in std_ulogic;
      bit_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pad_i : in nsl_io.diff.diff_pair_vector(0 to lane_count_c-1);
      lane_o : out cuff_code_vector(0 to lane_count_c-1);

      align_restart_i : in std_ulogic;
      align_valid_i : in std_ulogic_vector(0 to lane_count_c-1);
      align_ready_o : out std_ulogic_vector(0 to lane_count_c-1)
      );
  end component;
  
  component cuff_transmitter is
    generic(
      lane_count_c : natural
      );
    port(
      clock_i : in std_ulogic;
      bit_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      lane_i : in cuff_code_vector(0 to lane_count_c-1);
      pad_o : out std_ulogic_vector(0 to lane_count_c-1)
      );
  end component;

  component cuff_receiver is
    generic(
      lane_count_c : natural;
      input_fixed_delay_ps_c: natural := 0;
      has_input_alignment_c: boolean := true
      );
    port(
      clock_i : in std_ulogic;
      bit_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pad_i : in std_ulogic_vector(0 to lane_count_c-1);
      lane_o : out cuff_code_vector(0 to lane_count_c-1);

      align_restart_i : in std_ulogic;
      align_valid_i : in std_ulogic_vector(0 to lane_count_c-1);
      align_ready_o : out std_ulogic_vector(0 to lane_count_c-1)
      );
  end component;
      
end package transceiver;
