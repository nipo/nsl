library ieee;
use ieee.std_logic_1164.all;

library nsl_hwdep, nsl_indication;

entity top is
  port (
    led: out std_ulogic
  );
end top;

architecture arch of top is

  signal clock, reset_n: std_ulogic;

  type state_t is (
    ST_RESET,
    ST_S1,
    ST_O,
    ST_S2
    );

  signal state : state_t;
  signal valid, ready, last : std_ulogic;
  signal char : nsl_indication.morse.morse_character_t;
  signal led_n : std_ulogic;
  
begin

  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clock
      );

  reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock,
      reset_n_o => reset_n
      );

  led <= not led_n;
  
  morse: nsl_indication.morse.morse_encoder
    generic map(
      clock_rate_c => 50000000
      )
    port map(
      reset_n_i => reset_n,
      clock_i => clock,

      valid_i => valid,
      last_i => last,
      ready_o => ready,
      data_i => char,

      morse_o => led_n
      );
  
  process (reset_n, clock)
  begin
    if reset_n = '0' then
      state <= ST_RESET;
    elsif rising_edge(clock) then
      case state is
        when ST_RESET =>
          state <= ST_S1;

        when ST_S1 =>
          if ready = '1' then
            state <= ST_O;
          end if;

        when ST_O =>
          if ready = '1' then
            state <= ST_S2;
          end if;

        when ST_S2 =>
          if ready = '1' then
            state <= ST_S1;
          end if;
      end case;
    end if;
  end process;

  process (state)
  begin
    valid <= '0';
    char <= "--------";
    last <= '-';

    case state is
      when ST_RESET =>
        null;

      when ST_S1 =>
        char <= nsl_indication.morse.morse_s;
        last <= '0';
        valid <= '1';

      when ST_O =>
        char <= nsl_indication.morse.morse_o;
        last <= '0';
        valid <= '1';

      when ST_S2 =>
        char <= nsl_indication.morse.morse_s;
        last <= '1';
        valid <= '1';
    end case;
  end process;
  
end arch;
