library ieee;
use ieee.std_logic_1164.all;

library nsl_math, nsl_signal_generator;
use nsl_math.fixed.all;

entity sinus_stream is
  generic (
    scale_c : real := 1.0;
    implementation_c : string := "table"
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    value_o : out sfixed
    );
end sinus_stream;

architecture beh of sinus_stream is
begin

  assert implementation_c = "table"
    report "Unsupported implementation: " & implementation_c
    severity failure;

  use_table: if implementation_c = "table"
  generate
    impl: nsl_signal_generator.sinus.sinus_stream_table
      generic map(
        scale_c => scale_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        angle_i => angle_i,
        value_o => value_o
        );
  end generate;

end architecture;