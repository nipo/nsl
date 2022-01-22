library ieee;
use ieee.std_logic_1164.all;

library nsl_math, nsl_dsp;
use nsl_math.fixed.all;

-- Gaussian is approximated using successive RC filters.
-- Composing multiple convolution filters tends to a gaussian. All we
-- need is to guarantee unity gain. RC filters have unity gain.
--
-- Main idea comes from discussions in
-- https://dsp.stackexchange.com/questions/31483
entity gaussian_rc_ufixed is
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

architecture beh of gaussian_rc_ufixed is

  constant tau: natural := nsl_dsp.rc.tau_from_frequency(
    cutoff_frequency => bt_c * 8.0,
    run_frequency => real(symbol_sample_count_c),
    use_next_pow2m1 => true
    );
  constant count_c : integer := nsl_math.arith.log2(tau);
  subtype sample_t is ufixed(in_i'left downto in_i'right);
  type sample_vector is array(integer range <>) of sample_t;
  signal s_in, s_out : sample_vector(0 to count_c-2);
  
begin

  assert in_i'left = out_o'left and in_i'right = out_o'right
    report "Input and output data words are not the same size"
    severity failure;

  l: for i in s_in'range
  generate
    inst: nsl_dsp.rc.rc_ufixed
      generic map(
        tau_c => tau / (2**i)
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
