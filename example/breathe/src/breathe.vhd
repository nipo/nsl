library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_signal_generator, nsl_math;

entity top is
  port (
    led: out std_ulogic
  );
end top;

architecture arch of top is

  signal clock, reset_n: std_ulogic;

  type state_t is (
    ST_RESET,
    ST_UP,
    ST_DOWN
    );

  signal state : state_t;
  signal duty_cycle : unsigned(7 downto 0);
  signal duty_cycle_compl : unsigned(7 downto 0);
  signal sync : std_ulogic;
  constant pre : natural := 5 * 50000000 / (2 * 256) / 256;
  constant pre_w : positive := nsl_math.arith.log2(pre);
  constant pre_val : unsigned(pre_w-1 downto 0) := to_unsigned(pre, pre_w);

begin

  duty_cycle_compl <= (not duty_cycle) + 1;
  
  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clock
      );

  reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock,
      reset_n_o => reset_n
      );

  pwm: nsl_signal_generator.pwm.pwm_generator
    port map(
      reset_n_i => reset_n,
      clock_i => clock,

      prescaler_i => pre_val,
      active_duration_i => duty_cycle,
      inactive_duration_i => duty_cycle_compl,

      pwm_o => led,
      sync_o => sync
      );

  process (reset_n, clock)
  begin
    if reset_n = '0' then
      state <= ST_RESET;
    elsif rising_edge(clock) then
      case state is
        when ST_RESET =>
          state <= ST_UP;
          duty_cycle <= (others => '0');

        when ST_UP =>
          if sync = '1' then
            if duty_cycle /= (duty_cycle'range => '1') then
              duty_cycle <= duty_cycle + 1;
            else
              duty_cycle <= duty_cycle - 1;
              state <= ST_DOWN;
            end if;
          end if;

        when ST_DOWN =>
          if sync = '1' then
            if duty_cycle /= (duty_cycle'range => '0') then
              duty_cycle <= duty_cycle - 1;
            else
              duty_cycle <= duty_cycle + 1;
              state <= ST_UP;
            end if;
          end if;
      end case;
    end if;
  end process;
  
end arch;
