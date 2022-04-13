library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_io;
use nsl_cuff.protocol.all;
use nsl_io.diff.all;
  
entity cuff_diff_transmitter is
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
end entity;

architecture beh of cuff_diff_transmitter is

  signal se_s: std_ulogic_vector(0 to lane_count_c-1);

begin

  iter: for i in 0 to lane_count_c-1
  generate
  begin
    output: nsl_io.pad.pad_diff_output
      port map(
        p_se => se_s(i),
        p_diff => pad_o(i)
        );
  end generate;

  inst: nsl_cuff.transceiver.cuff_transmitter
    generic map(
      lane_count_c => lane_count_c
      )
    port map(
      clock_i => clock_i,
      bit_clock_i => bit_clock_i,
      reset_n_i => reset_n_i,

      pad_o => se_s,
      lane_i => lane_i
      );
  
end architecture;
