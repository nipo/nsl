library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

-- This is an exponentially weighted moving average where smoothing
-- factor is a = dt / (RC + dt)
--
-- With dt = 1 cycle and RC expressed in cycles, this boils down to:
-- a = 1 / (tau_c + 1)
--
-- every cycle:
--   acc += a * (in_i - acc)
--   out_o = acc
--
-- This costs one multiplier and two adders.
--
-- Nonetheless, this is could be optimized even further. If
-- multiplication by a is equivalent to a shift (i.e. tau_c + 1 is a
-- power of two), we can rewrite as.
--
-- every cycle:
--   acc += (in_i - acc) >> log2(tau_c + 1)
--   out_o = acc
--
-- Which only coses two adders

entity rc_sfixed is
  generic(
    -- Time constant, in cycles
    tau_c : natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i : in std_ulogic := '1';
    in_i : in sfixed;
    out_o : out sfixed
    );
end entity;

architecture beh of rc_sfixed is

  constant tau_w : integer := nsl_math.arith.log2(tau_c);
  constant can_shift : boolean := tau_c = ((2 ** tau_w) - 1);
  constant wl: integer := nsl_math.arith.max(in_i'left, out_o'left);
  constant wr: integer := nsl_math.arith.min(in_i'right, out_o'right);
  subtype acc_t is sfixed(wl+1 downto wr - tau_w);

  type regs_t is
  record
    acc : acc_t;
  end record;

  signal r, rin : regs_t;
  
begin

  assert tau_c >= 2
    report "Useless filter"
    severity failure;
  
  assert false
    report "Tau " & integer'image(tau_c)
    & ", tau_w " & integer'image(tau_w)
    & ", can_shift " & boolean'image(can_shift)
    severity note;
  
  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.acc <= (others => '0');
    end if;
  end process;

  transition: process(r, in_i, valid_i) is
    variable to_dec, to_add: acc_t;
    constant a : acc_t := to_sfixed(1.0 / real(tau_c + 1), acc_t'left, acc_t'right);
  begin
    rin <= r;

    to_add := (others => in_i(in_i'left));
    to_add(in_i'left - tau_w downto in_i'right-tau_w) := sfixed(in_i);

    if can_shift then
      to_dec := shr(r.acc, tau_w);
    else
      to_dec := mul(r.acc, a, to_dec'left, to_dec'right);
    end if;

    if valid_i = '1' then
      rin.acc <= r.acc + to_add - to_dec;
    end if;
  end process;

  out_o <= resize_saturate(r.acc, out_o'left, out_o'right);

end architecture;
