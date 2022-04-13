library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_io;
use nsl_cuff.protocol.all;

entity cuff_receiver is
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
end entity;

architecture beh of cuff_receiver is

begin

  iter: for i in 0 to lane_count_c-1
  generate
    signal delayed_s, delay_shift_s, delay_mark_s, slip_shift_s, slip_mark_s : std_ulogic;
  begin
    with_aligner: if has_input_alignment_c
    generate
      aligner: nsl_io.delay.input_delay_aligner
        generic map(
          stabilization_delay_c => 7,
          stabilization_cycle_c => 6
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          delay_shift_o => delay_shift_s,
          delay_mark_i => delay_mark_s,
          serdes_shift_o => slip_shift_s,
          serdes_mark_i => slip_mark_s,

          restart_i => align_restart_i,
          valid_i => align_valid_i(i),
          ready_o => align_ready_o(i)
          );

      delayer: nsl_io.delay.input_delay_variable
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,
          mark_o => delay_mark_s,
          shift_i => delay_shift_s,
          data_i => pad_i(i),
          data_o => delayed_s
          );
    end generate;

    without_aligner: if not has_input_alignment_c
    generate
      delay: nsl_io.delay.input_delay_fixed
        generic map(
          delay_ps_c => input_fixed_delay_ps_c,
          is_ddr_c => true
          )
        port map(
          data_i => pad_i(i),
          data_o => delayed_s
          );

      align_ready_o(i) <= '1';
    end generate;

    deserializer: nsl_io.serdes.serdes_ddr10_input
      port map(
        word_clock_i => clock_i,
        bit_clock_i => bit_clock_i,
        reset_n_i => reset_n_i,
        parallel_o => lane_o(i),
        serial_i => delayed_s,
        bitslip_i => slip_shift_s,
        mark_o => slip_mark_s
        );
  end generate;

end architecture;
