library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.calendar.all;

entity calendar_from_seconds is
  generic(
    epoch_year_c : natural := 1900
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    seconds_i : in unsigned(31 downto 0);

    date_time_o : out date_time_t;
    valid_o : out std_ulogic
    );
end entity;

architecture beh of calendar_from_seconds is

  constant seconds_per_day_c : natural := 86400;
  constant seconds_per_hour_c : natural := 3600;
  constant seconds_per_minute_c : natural := 60;

  type month_length_t is array (1 to 12) of natural;
  constant month_length_c : month_length_t
    := (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

  type state_t is (
    ST_START,
    ST_DIV_DAYS,
    ST_DIV_HOURS,
    ST_DIV_MINUTES,
    ST_YEAR,
    ST_MONTH,
    ST_DONE
    );

  type regs_t is
  record
    state : state_t;

    -- Restoring long division, one bit per cycle
    num : unsigned(31 downto 0);
    rem_acc : unsigned(31 downto 0);
    quot : unsigned(31 downto 0);
    bit_idx : natural range 0 to 31;

    days : unsigned(16 downto 0);
    year : unsigned(11 downto 0);
    -- Position of the year in the 4, 100 and 400 year leap cycles
    year_mod4 : natural range 0 to 3;
    year_mod100 : natural range 0 to 99;
    year_mod400 : natural range 0 to 399;
    month : natural range 1 to 12;

    date_time : date_time_t;
    valid : std_ulogic;
  end record;

  signal r, rin : regs_t;

  function is_leap(mod4 : natural; mod100 : natural; mod400 : natural)
    return boolean
  is
  begin
    return mod4 = 0 and (mod100 /= 0 or mod400 = 0);
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_START;
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, seconds_i) is
    variable divisor_v : unsigned(31 downto 0);
    variable rem_v, quot_v : unsigned(31 downto 0);
    variable year_length_v, month_length_v : unsigned(8 downto 0);
    variable leap_v : boolean;
  begin
    rin <= r;
    rin.valid <= '0';

    leap_v := is_leap(r.year_mod4, r.year_mod100, r.year_mod400);

    case r.state is
      when ST_START =>
        rin.num <= seconds_i;
        rin.rem_acc <= (others => '0');
        rin.quot <= (others => '0');
        rin.bit_idx <= 0;
        rin.year <= to_unsigned(epoch_year_c, 12);
        rin.year_mod4 <= epoch_year_c mod 4;
        rin.year_mod100 <= epoch_year_c mod 100;
        rin.year_mod400 <= epoch_year_c mod 400;
        rin.month <= 1;
        rin.state <= ST_DIV_DAYS;

      when ST_DIV_DAYS | ST_DIV_HOURS | ST_DIV_MINUTES =>
        case r.state is
          when ST_DIV_DAYS => divisor_v := to_unsigned(seconds_per_day_c, 32);
          when ST_DIV_HOURS => divisor_v := to_unsigned(seconds_per_hour_c, 32);
          when others => divisor_v := to_unsigned(seconds_per_minute_c, 32);
        end case;

        rem_v := r.rem_acc(30 downto 0) & r.num(31);
        if rem_v >= divisor_v then
          rem_v := rem_v - divisor_v;
          quot_v := r.quot(30 downto 0) & '1';
        else
          quot_v := r.quot(30 downto 0) & '0';
        end if;
        rin.num <= r.num(30 downto 0) & '0';
        rin.rem_acc <= rem_v;
        rin.quot <= quot_v;

        if r.bit_idx /= 31 then
          rin.bit_idx <= r.bit_idx + 1;
        else
          rin.bit_idx <= 0;
          rin.quot <= (others => '0');
          rin.rem_acc <= (others => '0');
          rin.num <= rem_v;
          case r.state is
            when ST_DIV_DAYS =>
              rin.days <= quot_v(16 downto 0);
              rin.state <= ST_DIV_HOURS;
            when ST_DIV_HOURS =>
              rin.date_time.hour <= quot_v(4 downto 0);
              rin.state <= ST_DIV_MINUTES;
            when others =>
              rin.date_time.minute <= quot_v(5 downto 0);
              rin.date_time.second <= rem_v(5 downto 0);
              rin.state <= ST_YEAR;
          end case;
        end if;

      when ST_YEAR =>
        if leap_v then
          year_length_v := to_unsigned(366, 9);
        else
          year_length_v := to_unsigned(365, 9);
        end if;

        if r.days >= resize(year_length_v, r.days'length) then
          rin.days <= r.days - resize(year_length_v, r.days'length);
          rin.year <= r.year + 1;
          if r.year_mod4 = 3 then
            rin.year_mod4 <= 0;
          else
            rin.year_mod4 <= r.year_mod4 + 1;
          end if;
          if r.year_mod100 = 99 then
            rin.year_mod100 <= 0;
          else
            rin.year_mod100 <= r.year_mod100 + 1;
          end if;
          if r.year_mod400 = 399 then
            rin.year_mod400 <= 0;
          else
            rin.year_mod400 <= r.year_mod400 + 1;
          end if;
        else
          rin.state <= ST_MONTH;
        end if;

      when ST_MONTH =>
        month_length_v := to_unsigned(month_length_c(r.month), 9);
        if r.month = 2 and leap_v then
          month_length_v := to_unsigned(29, 9);
        end if;

        if r.days >= resize(month_length_v, r.days'length) then
          rin.days <= r.days - resize(month_length_v, r.days'length);
          rin.month <= r.month + 1;
        else
          rin.state <= ST_DONE;
        end if;

      when ST_DONE =>
        rin.date_time.year <= r.year;
        rin.date_time.month <= to_unsigned(r.month, 4);
        rin.date_time.day <= resize(r.days + 1, 5);
        rin.valid <= '1';
        rin.state <= ST_START;
    end case;
  end process;

  moore: process(r) is
  begin
    date_time_o <= r.date_time;
    valid_o <= r.valid;
  end process;

end architecture;
