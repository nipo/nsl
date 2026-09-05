library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

entity discipline_second_setter is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';

    second_i : in unsigned(31 downto 0);
    second_valid_i : in std_ulogic;

    tick_i : in std_ulogic;

    timestamp_i : in timestamp_t;
    timestamp_o : out timestamp_t;
    timestamp_set_o : out std_ulogic
    );
end entity;

architecture beh of discipline_second_setter is

  -- Past this point in the second, the nanosecond field no longer
  -- tells which side of the boundary the time base stands on, so the
  -- second field it shows cannot be compared to the label.
  constant guard_ns_c : timestamp_nanosecond_t
    := to_unsigned(250000000, timestamp_nanosecond_t'length);

  type regs_t is
  record
    -- Second the time base must show at the next tick, one more than
    -- the last label received.
    expected : timestamp_second_t;
    armed : std_ulogic;

    timestamp : timestamp_t;
    set : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.armed <= '0';
      r.set <= '0';
    end if;
  end process;

  transition: process(r, enable_i, second_i, second_valid_i, tick_i,
                      timestamp_i) is
  begin
    rin <= r;

    rin.set <= '0';

    if tick_i = '1' then
      rin.armed <= '0';

      if r.armed = '1'
        and timestamp_i.second /= r.expected
        and timestamp_i.nanosecond < guard_ns_c then
        rin.timestamp.abs_change <= '1';
        rin.timestamp.second <= r.expected;
        rin.timestamp.nanosecond <= timestamp_i.nanosecond;
        rin.set <= '1';
      end if;
    end if;

    -- A label arriving on the tick cycle itself describes the epoch
    -- that tick opened: it arms for the next one.
    if second_valid_i = '1' then
      rin.expected <= second_i + 1;
      rin.armed <= '1';
    end if;

    if enable_i = '0' then
      rin.armed <= '0';
      rin.set <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    timestamp_o <= r.timestamp;
    timestamp_set_o <= r.set;
  end process;

end architecture;
