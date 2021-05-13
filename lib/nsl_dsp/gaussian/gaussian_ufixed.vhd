library ieee;
use ieee.std_logic_1164.all;

library nsl_dsp, nsl_math;
use nsl_math.fixed.all;

entity gaussian_ufixed is
  generic(
    symbol_sample_count_c : integer;
    bt_c : real;
    approximation_method_c : string := "box"
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in ufixed;
    out_o : out ufixed
    );
end entity;    

architecture beh of gaussian_ufixed is
  
begin

  use_box: if approximation_method_c = "box"
  generate
    impl: nsl_dsp.gaussian.gaussian_box_ufixed
      generic map(
        symbol_sample_count_c => symbol_sample_count_c,
        bt_c => bt_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        in_i => in_i,
        out_o => out_o
        );
  end generate;

  use_rc: if approximation_method_c = "rc"
  generate
    impl: nsl_dsp.gaussian.gaussian_rc_ufixed
      generic map(
        symbol_sample_count_c => symbol_sample_count_c,
        bt_c => bt_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        in_i => in_i,
        out_o => out_o
        );
  end generate;

  assert approximation_method_c = "box" or approximation_method_c = "rc"
    report "Unknown implementation required"
    severity failure;
  
end architecture;
