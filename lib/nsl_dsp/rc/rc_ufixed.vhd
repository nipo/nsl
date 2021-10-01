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

entity rc_ufixed is
  generic(
    -- Time constant, in cycles
    tau_c : natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i : in std_ulogic := '1';
    in_i : in ufixed;
    out_o : out ufixed
    );
end entity;

architecture beh of rc_ufixed is

  constant tau_w : integer := nsl_math.arith.log2(tau_c);
  constant can_shift : boolean := tau_c = ((2 ** tau_w) - 1);
  constant wl: integer := nsl_math.arith.max(in_i'left, out_o'left);
  constant wr: integer := nsl_math.arith.min(in_i'right, out_o'right);
  subtype uacc_t is ufixed(wl downto wr - tau_w);
  subtype diff_t is ufixed(wl downto wr);

  type regs_t is
  record
    acc : uacc_t;
  end record;

  signal s_diff: diff_t;
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

  with_shift: if can_shift
  generate
    s_diff <= resize(in_i, s_diff'left, s_diff'right)
            - resize(r.acc, s_diff'left, s_diff'right);

  end generate;

  without_shift: if not can_shift
  generate
    diff_calc: process(r, in_i) is
      subtype sacc_t is sfixed(wl+1 downto wr - tau_w);
      constant a : sacc_t := to_sfixed(1.0 / real(tau_c + 1), sacc_t'left, sacc_t'right);
      variable sin: sfixed(in_i'left+1 downto in_i'right);
      variable sacc, sin_ext, sdiff, sinc : sacc_t;
    begin
      rin <= r;

      sin := sfixed("0" & in_i);
      sacc := sfixed("0" & r.acc);

      sin_ext := resize(sin, sacc_t'left, sacc_t'right);
      sdiff := sin_ext - sacc;
      s_diff <= ufixed(mul(sdiff, a, s_diff'left, s_diff'right));
    end process;
  end generate;

  transition: process(r, s_diff, valid_i) is
    variable sdiff : ufixed(uacc_t'range);
    variable sext : ufixed(tau_w-1 downto 0);
  begin
    rin <= r;

    sext := (others => s_diff(s_diff'left));
    sdiff := sext & s_diff;
    if valid_i = '1' then
      rin.acc <= r.acc + sdiff;
    end if;
  end process;

  out_o <= resize(r.acc, out_o'left, out_o'right);

end architecture;
