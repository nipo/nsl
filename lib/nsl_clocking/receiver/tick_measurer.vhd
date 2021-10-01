library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library nsl_math, nsl_dsp;
use nsl_math.fixed.all;

entity tick_measurer is
  generic (
    tau_c : natural
    );
  port (
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;
    tick_i : in std_ulogic;
    period_o : out ufixed
    );
end tick_measurer;

architecture rtl of tick_measurer is
  
  constant unit_c : ufixed(period_o'left downto 0) := (0 => '1', others => '0');

  type regs_t is
  record
    counter: ufixed(unit_c'range);
    period: ufixed(unit_c'range);
    valid: std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.counter <= unit_c;
      r.period <= unit_c;
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, tick_i) is
  begin
    rin <= r;

    rin.valid <= tick_i;
    if r.valid = '1' then
      rin.counter <= unit_c;
      rin.period <= r.counter;
    else
      rin.counter <= r.counter + unit_c;
    end if;
  end process;

  rc: nsl_dsp.rc.rc_ufixed
    generic map(
      tau_c => tau_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      valid_i => r.valid,
      in_i => r.counter,
      out_o => period_o
      );

end rtl;
