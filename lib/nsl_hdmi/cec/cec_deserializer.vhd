library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_clocking, nsl_logic;
use nsl_math.timing.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.cec.all;

entity cec_deserializer is
  generic(
    clock_i_hz_c: natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    cec_i : in std_ulogic;

    idle_o: out std_ulogic;
    ack_window_o : out std_ulogic;
    valid_o: out std_ulogic;
    symbol_o: out cec_symbol_t
    );
end entity;

architecture beh of cec_deserializer is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WAIT_HOLD,
    ST_WAIT_SAMPLE,
    ST_WAIT_RELEASE,
    ST_WAIT_BITEND,
    ST_WAIT_START_END,
    ST_WAIT_HIGH
    );

  -- Ts to where we may hold acknowledge
  constant ts_to_hold_c: natural := to_cycles(100 us, clock_i_hz_c);
  -- Previous timing to nominal sample time
  constant hold_to_sample_c: natural := to_cycles(1050 us - 100 us, clock_i_hz_c);
  -- T4/T5 to where we may release acknowledge
  constant sample_to_release_c: natural := to_cycles(1500 us - 1050 us, clock_i_hz_c);
  -- Previous to T7/T8 timing
  constant release_to_bitend_c: natural := to_cycles(1900 us - 1500 us, clock_i_hz_c);
  -- Previous to date between a and b on start bit timing
  constant bitend_to_startend_c: natural := to_cycles(4000 us - 1900 us, clock_i_hz_c);
  constant bit_duration_c: natural := to_cycles(cec_bit_period_c, clock_i_hz_c);

  constant all_reloads_c : integer_vector := (
    ts_to_hold_c, hold_to_sample_c, sample_to_release_c, release_to_bitend_c,
    bitend_to_startend_c, bit_duration_c);
  constant reload_max_c: natural := nsl_math.int_ext.max(all_reloads_c);

  type regs_t is
  record
    timer: natural range 0 to reload_max_c - 1;
    had_falling: boolean;
    cec : std_ulogic;
    state: state_t;
    symbol: cec_symbol_t;
    symbol_valid: boolean;
  end record;

  signal r, rin: regs_t;

  signal cec_s : std_ulogic;
  
begin

  debouncer: nsl_clocking.async.async_deglitcher
    port map(
      clock_i => clock_i,
      data_i => cec_i,
      data_o => cec_s
      );
  
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, cec_s) is
  begin
    rin <= r;

    rin.symbol_valid <= false;
    rin.cec <= cec_s;

    case r.state is
      when ST_RESET =>
        rin.had_falling <= false;
        rin.state <= ST_IDLE;
        rin.timer <= bit_duration_c - 1;

      when ST_IDLE =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= bit_duration_c - 1;
          rin.symbol_valid <= true;
          rin.symbol <= CEC_SYMBOL_IDLE;
        end if;

        if r.had_falling then
          rin.state <= ST_WAIT_HOLD;
          rin.timer <= ts_to_hold_c - 1;
          rin.had_falling <= false;
        end if;

      when ST_WAIT_HOLD =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_WAIT_SAMPLE;
          rin.timer <= hold_to_sample_c - 1;
        end if;

      when ST_WAIT_SAMPLE =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        elsif r.had_falling then
          rin.had_falling <= false;
          rin.state <= ST_WAIT_HIGH;
          rin.symbol_valid <= true;
          rin.symbol <= CEC_SYMBOL_INVALID;
        else
          rin.state <= ST_WAIT_RELEASE;
          rin.timer <= sample_to_release_c - 1;
          if r.cec = '1' then
            rin.symbol <= CEC_SYMBOL_1;
          else
            rin.symbol <= CEC_SYMBOL_0;
          end if;
        end if;

      when ST_WAIT_RELEASE =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_WAIT_BITEND;
          rin.timer <= release_to_bitend_c - 1;
        end if;

      when ST_WAIT_BITEND =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        elsif r.had_falling then
          rin.had_falling <= false;
          rin.state <= ST_WAIT_HIGH;
          rin.symbol_valid <= true;
          rin.symbol <= CEC_SYMBOL_INVALID;
        elsif r.cec = '0' and r.symbol = CEC_SYMBOL_0 then
          rin.state <= ST_WAIT_START_END;
          rin.timer <= bitend_to_startend_c - 1;
        else
          rin.symbol_valid <= true;
          rin.state <= ST_IDLE;
          rin.timer <= bit_duration_c - 1;
        end if;

      when ST_WAIT_START_END =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        elsif r.had_falling or r.cec = '0' then
          rin.had_falling <= false;
          rin.state <= ST_WAIT_HIGH;
          rin.symbol_valid <= true;
          rin.symbol <= CEC_SYMBOL_INVALID;
        else
          rin.symbol <= CEC_SYMBOL_START;
          rin.symbol_valid <= true;
          rin.state <= ST_IDLE;
          rin.timer <= bit_duration_c - 1;
        end if;

      when ST_WAIT_HIGH =>
        if r.cec = '1' then
          rin.state <= ST_IDLE;
          rin.timer <= bit_duration_c - 1;
        end if;
    end case;
        
    if r.cec = '1' and cec_s = '0' then
      rin.had_falling <= true;
    end if;
  end process;

  moore: process(r) is
  begin
    valid_o <= to_logic(r.symbol_valid);
    symbol_o <= r.symbol;
    idle_o <= '0';
    ack_window_o <= '0';

    case r.state is
      when ST_IDLE =>
        idle_o <= '1';
      when ST_WAIT_SAMPLE | ST_WAIT_RELEASE =>
        ack_window_o <= '1';
      when others =>
        null;
    end case;
  end process;

end architecture;

