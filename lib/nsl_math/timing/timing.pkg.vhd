library ieee;
use ieee.numeric_std.all;
use ieee.math_real.all;

package timing is

  function to_seconds(t : time) return real;
  function to_cycles(seconds: real; clock_rate: real; min_cycles : natural := 1) return natural;
  function to_cycles(t : time; clock_rate: real; min_cycles : natural := 1) return natural;
  function to_cycles(seconds: real; clock_rate: natural; min_cycles : natural := 1) return natural;
  function to_cycles(t : time; clock_rate: natural; min_cycles : natural := 1) return natural;

end package timing;

package body timing is

  function to_seconds(t : time) return real
  is
  begin
    if t < 1 ns then
      return 1.0e-15 * real(t / 1 fs);
    elsif t < 1 us then
      return 1.0e-12 * real(t / 1 ps);
    elsif t < 1 ms then
      return 1.0e-9 * real(t / 1 ns);
    elsif t < 1 sec then
      return 1.0e-6 * real(t / 1 us);
    elsif t < 1e3 sec then
      return 1.0e-3 * real(t / 1 ms);
    else
      return real(t / 1 sec);
    end if;
  end function;

  function to_cycles(seconds: real; clock_rate: real; min_cycles : natural := 1) return natural
  is
    constant cycles: natural := natural(ceil(seconds * clock_rate));
  begin
    if cycles < min_cycles then
      return min_cycles;
    else
      return cycles;
    end if;
  end function;
    
  function to_cycles(t : time; clock_rate: real; min_cycles : natural := 1) return natural
  is
  begin
    return to_cycles(to_seconds(t), clock_rate, min_cycles);
  end function;

  function to_cycles(seconds: real; clock_rate: natural; min_cycles : natural := 1) return natural
  is
  begin
    return to_cycles(seconds, real(clock_rate), min_cycles);
  end function;

  function to_cycles(t : time; clock_rate: natural; min_cycles : natural := 1) return natural
  is
  begin
    return to_cycles(t, real(clock_rate), min_cycles);
  end function;

end package body timing;
