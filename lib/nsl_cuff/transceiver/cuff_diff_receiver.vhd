library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_io;
use nsl_cuff.protocol.all;
use nsl_io.diff.all;
  
entity cuff_diff_receiver is
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

    pad_i : in diff_pair_vector(0 to lane_count_c-1);
    lane_o : out cuff_code_vector(0 to lane_count_c-1);

    align_restart_i : in std_ulogic;
    align_valid_i : in std_ulogic_vector(0 to lane_count_c-1);
    align_ready_o : out std_ulogic_vector(0 to lane_count_c-1)
    );
end entity;

architecture beh of cuff_diff_receiver is

  signal se_s: std_ulogic_vector(0 to lane_count_c-1);

begin

  iter: for i in 0 to lane_count_c-1
  generate
  begin
    input: nsl_io.pad.pad_diff_input
      generic map(
        diff_term => diff_term
        )
      port map(
        p_se => se_s(i),
        p_diff => pad_i(i)
        );
  end generate;

  inst: nsl_cuff.transceiver.cuff_receiver
    generic map(
      lane_count_c => lane_count_c,
      input_fixed_delay_ps_c => input_fixed_delay_ps_c,
      has_input_alignment_c => has_input_alignment_c
      )
    port map(
      clock_i => clock_i,
      bit_clock_i => bit_clock_i,
      reset_n_i => reset_n_i,
      pad_i => se_s,
      lane_o => lane_o,
      align_restart_i => align_restart_i,
      align_valid_i => align_valid_i,
      align_ready_o => align_ready_o
      );
  
end architecture;
