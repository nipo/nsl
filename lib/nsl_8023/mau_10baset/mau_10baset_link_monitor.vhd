library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mau_10baset_link_monitor is
  generic (
    clock_i_hz_c : natural;
    slow_timer_div_c : natural := 1
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    link_pulse_i : in std_ulogic;
    frame_i : in std_ulogic;

    link_up_o : out std_ulogic
    );
end entity;

architecture beh of mau_10baset_link_monitor is

  constant ms_cycles_c : natural := clock_i_hz_c / 1000 / slow_timer_div_c;
  -- Link pulses closer than this are ignored, they are considered
  -- ringing of a previous one.
  constant min_cycles_c : natural := 2 * ms_cycles_c;
  -- A link pulse arriving later than this restarts the count.
  constant max_cycles_c : natural := 24 * ms_cycles_c;
  -- Without any receive activity for this long, link goes down.
  constant timeout_cycles_c : natural := 100 * ms_cycles_c;
  -- Consecutive correctly spaced link pulses needed to bring link up.
  constant pulse_count_c : natural := 4;

  type regs_t is
  record
    -- Cycles since last accepted receive activity, saturating.
    since : natural range 0 to timeout_cycles_c;
    count : natural range 0 to pulse_count_c;
    up : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.since <= 0;
      r.count <= 0;
      r.up <= '0';
    end if;
  end process;

  transition: process(r, link_pulse_i, frame_i) is
  begin
    rin <= r;

    if r.since /= timeout_cycles_c then
      rin.since <= r.since + 1;
    end if;

    if frame_i = '1' then
      rin.since <= 0;
      rin.count <= pulse_count_c;
      rin.up <= '1';
    elsif link_pulse_i = '1' then
      if r.since > max_cycles_c then
        rin.since <= 0;
        rin.count <= 1;
      elsif r.since >= min_cycles_c then
        rin.since <= 0;
        if r.count = pulse_count_c - 1 then
          rin.count <= pulse_count_c;
          rin.up <= '1';
        elsif r.count /= pulse_count_c then
          rin.count <= r.count + 1;
        end if;
      end if;
    elsif r.since = timeout_cycles_c then
      rin.count <= 0;
      rin.up <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    link_up_o <= r.up;
  end process;

end architecture;
