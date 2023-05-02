library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_logic;

entity complementary_led_driver is
  generic (
    clock_hz_c : in real;
    blink_rate_c : in real := 1.0e3;
    pow2_divisor_c : in boolean := true
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    led_i         : in  std_ulogic_vector(0 to 1);
    led_k_o       : out std_ulogic_vector(0 to 1)
    );
end entity;

architecture beh of complementary_led_driver is

  constant prescaler_exact_c : integer := integer(clock_hz_c / blink_rate_c / 2.0);
  constant prescaler_pow2_c : integer := nsl_math.arith.align_up(prescaler_exact_c);
  constant prescaler_c : integer := nsl_logic.bool.if_else(pow2_divisor_c,
                                                           prescaler_pow2_c,
                                                           prescaler_exact_c);
  
  type regs_t is
  record
    prescaler: integer range 0 to prescaler_c - 1;
    value : std_ulogic_vector(0 to 1);
    toggle : boolean;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.prescaler <= 0;
      r.toggle <= false;
    end if;
  end process;

  transition: process(r, led_i) is
  begin
    rin <= r;

    if nsl_math.arith.is_pow2(prescaler_c) then
      rin.prescaler <= (r.prescaler - 1) mod prescaler_c;
    else
      if r.prescaler /= 0 then
        rin.prescaler <= r.prescaler - 1;
      else
        rin.prescaler <= prescaler_c - 1;
      end if;
    end if;

    if r.prescaler = 0 then
      rin.value <= led_i;
      rin.toggle <= not r.toggle;
    end if;
  end process;

  moore: process(r) is
  begin
    if r.toggle then
      led_k_o <= '0' & r.value(0);
    else
      led_k_o <= r.value(1) & '0';
    end if;
  end process;

end architecture beh;
