library ieee;
use ieee.std_logic_1164.all;

library nsl_io, work;

entity dvi_driver is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;
    serial_clock_i : in std_ulogic;

    tmds_i : in work.dvi.symbol_vector_t;

    clock_o : out nsl_io.diff.diff_pair;
    data_o : out nsl_io.diff.diff_pair_vector(0 to 2)
    );
end entity;

architecture beh of dvi_driver is

  signal ser_s : std_ulogic_vector(0 to 2);
  signal clk_s : std_ulogic;

begin

  lanes: for i in 0 to 2
  generate
    ser: nsl_io.serdes.serdes_ddr10_output
      generic map(
        left_to_right_c => false
        )
      port map(
        bit_clock_i => serial_clock_i,
        word_clock_i => pixel_clock_i,
        reset_n_i => reset_n_i,
        parallel_i => std_ulogic_vector(tmds_i(i)),
        serial_o => ser_s(i)
        );

    pad: nsl_io.pad.pad_tmds_output
      port map(
        data_i => ser_s(i),
        pad_o => data_o(i)
        );
  end generate;

  ck_ser: nsl_io.serdes.serdes_ddr10_output
    generic map(
      left_to_right_c => false
      )
    port map(
      bit_clock_i => serial_clock_i,
      word_clock_i => pixel_clock_i,
      reset_n_i => reset_n_i,
      parallel_i => "1111100000",
      serial_o => clk_s
      );

  ck_pad: nsl_io.pad.pad_tmds_output
    port map(
      data_i => clk_s,
      pad_o => clock_o
      );

end architecture;
