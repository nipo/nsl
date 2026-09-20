library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;

-- Turns keys being pressed into things happening.
--
-- A key gives one pulse when it goes down, and then, if it is kept
-- down, another every period_ms_c after the first delay_ms_c.  That
-- is what makes a knob with two buttons usable: a tap moves it one
-- step and a hold runs it along.
--
-- Contacts bounce, and a pin is nothing to do with this clock, so
-- every key goes through a debouncer on the way in.
entity key_repeater is
  generic(
    clock_hz_c : natural;
    settle_us_c : natural := 5000;
    delay_ms_c : natural := 400;
    period_ms_c : natural := 80
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    key_i : in std_ulogic_vector;
    pulse_o : out std_ulogic_vector
    );
end entity;

architecture beh of key_repeater is

  constant millisecond_c : natural := clock_hz_c / 1000;

  subtype key_range_t is natural range key_i'range;
  subtype keys_t is std_ulogic_vector(key_i'range);
  type countdown_vector is array (natural range <>) of natural range 0 to delay_ms_c;

  type regs_t is
  record
    -- Milliseconds, counted down from the clock
    tick: natural range 0 to millisecond_c-1;
    held: keys_t;
    left: countdown_vector(key_i'range);
    pulse: keys_t;
  end record;

  signal r, rin: regs_t;
  signal settled_s: keys_t;

begin

  assert delay_ms_c >= period_ms_c
    report "A key repeats sooner than it starts repeating"
    severity failure;

  debouncers: for i in key_range_t
  generate
    settle: nsl_clocking.async.async_debouncer
      generic map(
        clock_i_hz_c => clock_hz_c,
        stable_us_c => settle_us_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        data_i => key_i(i),
        data_o => settled_s(i)
        );
  end generate;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.tick <= millisecond_c-1;
      r.held <= (others => '0');
      r.left <= (others => 0);
      r.pulse <= (others => '0');
    end if;
  end process;

  transition: process(r, settled_s) is
    variable millisecond: boolean;
  begin
    rin <= r;
    rin.pulse <= (others => '0');

    millisecond := r.tick = 0;
    if millisecond then
      rin.tick <= millisecond_c-1;
    else
      rin.tick <= r.tick - 1;
    end if;

    for i in key_range_t
    loop
      if settled_s(i) = '0' then
        rin.held(i) <= '0';
        rin.left(i) <= 0;
      elsif r.held(i) = '0' then
        rin.held(i) <= '1';
        rin.pulse(i) <= '1';
        rin.left(i) <= delay_ms_c;
      elsif millisecond and r.left(i) /= 0 then
        if r.left(i) = 1 then
          rin.pulse(i) <= '1';
          rin.left(i) <= period_ms_c;
        else
          rin.left(i) <= r.left(i) - 1;
        end if;
      end if;
    end loop;
  end process;

  pulse_o <= r.pulse;

end architecture;
