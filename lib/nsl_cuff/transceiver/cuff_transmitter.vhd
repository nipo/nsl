library ieee;
use ieee.std_logic_1164.all;

library nsl_cuff, nsl_line_coding, nsl_io;
use nsl_cuff.protocol.all;
  
entity cuff_transmitter is
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
end entity;

architecture beh of cuff_transmitter is
  
begin

  iter: for i in 0 to lane_count_c-1
  generate
    serializer: nsl_io.serdes.serdes_ddr10_output
      port map(
        word_clock_i => clock_i,
        bit_clock_i => bit_clock_i,
        reset_n_i => reset_n_i,
        parallel_i => lane_i(i),
        serial_o => pad_o(i)
        );
  end generate;
  
end architecture;
