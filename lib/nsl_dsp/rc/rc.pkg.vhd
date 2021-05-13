library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package rc is

  -- This is a RC filter. Its main characteristic is the time
  -- constant, when output reaches 63% of target value.
  --
  -- Implementation is more optimal when tau_c is 2^n - 1 (whatever n)
  --
  -- input and output ranges may not match. All calculation is
  -- performed on input range and tau_c dynamic range.
  component rc_ufixed is
    generic(
      -- Time constant, in cycles.
      -- Smoothing factor will be 1/(tau_c+1).
      tau_c : natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in ufixed;
      out_o : out ufixed
      );
  end component;    

  -- Calculate tau_c constant suitable for rc_ufixed in
  -- accordance to cutoff frequency and instance running frequency.
  --
  -- Optionally return next power-of-two-minus-one value.
  -- This may lower cutoff frequency.
  function tau_from_frequency(cutoff_frequency : real;
                              run_frequency : real;
                              use_next_pow2m1 : boolean := false)
    return natural;
  
end package rc;

package body rc is

  function tau_from_frequency(cutoff_frequency : real;
                              run_frequency : real;
                              use_next_pow2m1 : boolean := false)
    return natural
  is
    constant tau_sec : real := 1.0 / cutoff_frequency;
    constant tau_cycles : integer := integer(tau_sec * run_frequency);
  begin
    assert tau_cycles >= 1
      report "Cutoff frequency is above what is achievable"
      severity failure;

    if use_next_pow2m1 then
      return 2 ** (nsl_math.arith.log2(tau_cycles)) - 1;
    end if;

    return tau_cycles;
  end function;

end package body;
