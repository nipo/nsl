library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_clocking;

entity activity_blinker is
  generic (
    clock_hz_c : real;
    idle_blink_hz_c : real := 1.0;
    mode_c: string := "change";
    activity_blink_hz_c : real := 4.0;
    activity_blink_duration_c: real := 0.25
    );
  port (
    reset_n_i  : in  std_ulogic;
    clock_i    : in  std_ulogic;
    activity_i : in  std_ulogic;
    led_o      : out std_ulogic
    );
end activity_blinker;

architecture rtl of activity_blinker is

  constant activity_cycles_c : natural := integer(clock_hz_c / activity_blink_hz_c / 2.0);
  constant idle_cycles_c : natural := integer(clock_hz_c / idle_blink_hz_c / 2.0);
  constant counter_max_c : natural := nsl_math.arith.max(activity_cycles_c, idle_cycles_c);
  constant activity_duration_c : natural := integer(clock_hz_c * activity_blink_duration_c);
  constant activity_periods_c : natural := (activity_duration_c + activity_cycles_c - 1) / activity_cycles_c;

  type regs_t is record
    div: natural range 0 to counter_max_c-1;
    count: natural range 0 to activity_periods_c-1;
    led: std_ulogic;
    activity : std_ulogic;
  end record;

  signal r, rin: regs_t;
  signal rising_s, falling_s, activity_s, value_s: std_ulogic;

begin

  deglitcher: nsl_clocking.async.async_input
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => activity_i,
      data_o => value_s,
      rising_o => rising_s,
      falling_o => falling_s
      );

  mode_change: if mode_c = "change"
  generate
    activity_s <= rising_s or falling_s;
  end generate;
  
  mode_rising: if mode_c = "rising"
  generate
    activity_s <= rising_s;
  end generate;

  mode_falling: if mode_c = "falling"
  generate
    activity_s <= falling_s;
  end generate;

  mode_1: if mode_c = "1"
  generate
    activity_s <= value_s;
  end generate;

  mode_0: if mode_c = "0"
  generate
    activity_s <= not value_s;
  end generate;

  assert mode_c = "0" or mode_c = "1" or mode_c = "falling" or mode_c = "rising" or mode_c = "change"
    report "Bad mode"
    severity failure;
  
  process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.div <= 0;
      r.led <= '0';
    end if;
  end process;

  process (r, activity_s)
  begin
    rin <= r;

    rin.activity <= activity_s;

    if r.activity = '0' and activity_s = '1' then
      if r.count = 0 then
        rin.led <= not r.led;
        rin.div <= activity_cycles_c-1;
      end if;
      rin.count <= activity_periods_c-1;
    elsif r.div /= 0 then
      rin.div <= r.div - 1;
    else
      if r.count /= 0 then
        rin.count <= r.count - 1;
      end if;

      rin.led <= not r.led;
      if activity_s = '1' or r.count /= 0 then
        rin.div <= activity_cycles_c-1;
      else
        rin.div <= idle_cycles_c-1;
      end if;
    end if;
  end process;

  led_o <= r.led;
  
end rtl;
