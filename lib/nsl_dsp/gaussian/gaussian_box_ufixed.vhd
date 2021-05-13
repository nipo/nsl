library ieee;
use ieee.std_logic_1164.all;

library nsl_math, nsl_dsp;
use nsl_math.fixed.all;

-- Gaussian is approximated using successive box filters.  This works
-- because stupid approximation of gaussian is a box filter, and
-- composition of multiple gaussians is a gaussian.
--
-- Composing multiple box filters while doubling their length each
-- time gets closer to the actual gaussian response.
--
-- Main idea comes from discussions in
-- https://dsp.stackexchange.com/questions/31483
entity gaussian_box_ufixed is
  generic(
    symbol_sample_count_c : integer;
    bt_c : real
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in ufixed;
    out_o : out ufixed
    );
end entity;    

architecture beh of gaussian_box_ufixed is

  constant count_c: integer := nsl_math.arith.max(1, integer(ieee.math_real.log2(real(symbol_sample_count_c) / bt_c)+0.5)-1);
  subtype sample_t is ufixed(in_i'left downto in_i'right);
  type sample_vector is array(integer range <>) of sample_t;
  signal s_in, s_out : sample_vector(0 to count_c - 1);
  
begin

  assert in_i'left = out_o'left and in_i'right = out_o'right
    report "Input and output data words are not the same size"
    severity failure;

  l: for i in s_in'range
  generate
    inst: nsl_dsp.box.box_ufixed
      generic map(
        count_l2_c => i+1
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => s_in(i),
        out_o => s_out(i)
        );
  end generate;

  s_in <= in_i &  s_out(0 to s_out'right-1);
  out_o <= s_out(s_out'right);
  
end architecture;
