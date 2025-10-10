library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_data, nsl_logic;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_math.fixed.all;

entity probability_stream is
  generic (
    state_width_c: integer range 1 to 31 := 8
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    probability_i : in nsl_math.fixed.ufixed(-1 downto -state_width_c);

    ready_i : in std_ulogic := '1';
    value_o : out std_ulogic
    );
end entity;

architecture beh of probability_stream is

  subtype proba_t is unsigned(state_width_c-1 downto 0);

  type regs_t is
  record
    proba, cmp: proba_t;
    prbs: prbs_state(0 to 30);
    value: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.prbs <= x"deadbee"&"111";
    end if;
  end process;

  transition: process(r, ready_i, probability_i) is
  begin
    rin <= r;
    rin.proba <= to_unsigned(probability_i);

    if ready_i = '1' then
      rin.prbs <= prbs_forward(r.prbs, prbs31, r.cmp'length);
      rin.cmp <= unsigned(prbs_bit_string(r.prbs, prbs31, r.cmp'length));
      rin.value <= to_logic(r.cmp <= r.proba);
    end if;
  end process;

  value_o <= r.value;
  
end architecture;
