library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity pwm_generator is
  port (
    reset_n_i      : in  std_ulogic;
    clock_i         : in  std_ulogic;

    sync_i : in std_ulogic := '0';
    sync_o : out std_ulogic;

    pwm_o : out std_ulogic;

    prescaler_i : in unsigned;
    active_duration_i : in unsigned;
    inactive_duration_i : in unsigned;
    active_value_i : std_ulogic := '1'
    );
end entity;

architecture beh of pwm_generator is

  constant counter_width_c : positive := nsl_math.arith.max(active_duration_i'length,
                                                            inactive_duration_i'length);
  
  type regs_t is
  record
    prescaler_duration : unsigned(prescaler_i'length-1 downto 0);
    inactive_duration : unsigned(inactive_duration_i'length-1 downto 0);
    active_value : std_ulogic;

    prescaler : unsigned(prescaler_i'length-1 downto 0);
    counter : unsigned(counter_width_c-1 downto 0);
    active : boolean;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      r.active <= false;
      r.prescaler <= (others => '0');
      r.counter <= (others => '0');
      r.active_value <= '1';
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(active_duration_i, active_value_i, inactive_duration_i,
                      prescaler_i, r, sync_i) is
    variable update : boolean;
  begin
    rin <= r;
    update := sync_i = '1';

    if r.prescaler /= 0 then
      rin.prescaler <= r.prescaler - 1;
    elsif r.counter /= 0 then
      rin.counter <= r.counter - 1;
      rin.prescaler <= r.prescaler_duration;
    else
      rin.active <= false;
      if r.active then
        rin.counter <= resize(r.inactive_duration, counter_width_c);
        rin.active <= false;
      else
        update := true;
      end if;
    end if;

    if update then
      rin.prescaler <= prescaler_i;
      rin.prescaler_duration <= prescaler_i;
      rin.inactive_duration <= inactive_duration_i;
      rin.counter <= resize(active_duration_i, counter_width_c);
      rin.active_value <= active_value_i;
      rin.active <= true;
    end if;
  end process;

  pwm_o <= r.active_value when r.active else (not r.active_value);
  sync_o <= '1' when not r.active and r.prescaler = 0 and r.counter = 0 else '0';
  
end architecture;
