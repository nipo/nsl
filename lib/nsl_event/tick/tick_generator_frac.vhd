library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

entity tick_generator_frac is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    freq_num_i : in ufixed;
    freq_denom_i : in ufixed;
    
    tick_o   : out std_ulogic
    );
end entity;

architecture beh of tick_generator_frac is

  constant msb: integer := nsl_math.arith.max(freq_num_i'left, freq_denom_i'left) + 2;
  constant lsb: integer := nsl_math.arith.max(freq_num_i'right, freq_denom_i'right);
  subtype acc_t is sfixed(msb downto lsb);

  type regs_t is
  record
    num, num2, num_minus_denom, acc, denom: acc_t;
    tick: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.acc <= (others => '0');
      r.num <= (others => '0');
      r.denom <= (others => '0');
      r.num_minus_denom <= (others => '0');
      r.tick <= '0';
    end if;
  end process;

  transition: process(r, freq_num_i, freq_denom_i) is
  begin
    rin <= r;

    rin.denom <= to_sfixed(freq_denom_i, msb, lsb);
    rin.num <= to_sfixed(freq_num_i, msb, lsb);

    rin.num_minus_denom <= r.num - r.denom;
    rin.num2 <= r.num;

    if sign(r.acc) = '1' then
      rin.acc <= r.acc - r.num_minus_denom;
      rin.tick <= '1';
    else
      rin.acc <= r.acc - r.num2;
      rin.tick <= '0';
    end if;
  end process;

  tick_o <= r.tick;
  
end architecture;
