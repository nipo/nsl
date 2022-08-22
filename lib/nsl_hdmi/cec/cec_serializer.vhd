library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_clocking, nsl_logic, nsl_io;
use nsl_math.timing.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.cec.all;

entity cec_serializer is
  generic(
    clock_i_hz_c: natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    cec_o : out nsl_io.io.opendrain;

    ready_o: out std_ulogic;
    valid_i: in std_ulogic;
    symbol_i: in cec_symbol_t
    );
end entity;

architecture beh of cec_serializer is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_BIT_PRE,
    ST_BIT_VAL,
    ST_BIT_POST,
    ST_START_LOW,
    ST_START_HIGH
    );

  constant bit_pre_duration_c: natural := to_cycles(cec_bit_1_time_c, clock_i_hz_c);
  constant bit_value_duration_c: natural := to_cycles(cec_bit_0_time_c - cec_bit_1_time_c, clock_i_hz_c);
  constant bit_post_duration_c: natural := to_cycles(cec_bit_period_c - cec_bit_0_time_c, clock_i_hz_c);

  constant start_low_duration_c: natural := to_cycles(cec_start_low_time_c, clock_i_hz_c);
  constant start_high_duration_c: natural := to_cycles(cec_start_period_c - cec_start_low_time_c, clock_i_hz_c);

  constant all_reloads_c : integer_vector := (
    bit_pre_duration_c, bit_value_duration_c, bit_post_duration_c,
    start_low_duration_c, start_high_duration_c);
  constant reload_max_c: natural := nsl_math.int_ext.max(all_reloads_c);

  type regs_t is
  record
    timer: natural range 0 to reload_max_c - 1;
    state: state_t;
    bit_val: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin
  
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, valid_i, symbol_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          case symbol_i is
            when CEC_SYMBOL_START =>
              rin.state <= ST_START_LOW;
              rin.timer <= start_low_duration_c - 1;
            when CEC_SYMBOL_0 =>
              rin.bit_val <= '0';
              rin.state <= ST_BIT_PRE;
              rin.timer <= bit_pre_duration_c - 1;
            when CEC_SYMBOL_1 =>
              rin.bit_val <= '1';
              rin.state <= ST_BIT_PRE;
              rin.timer <= bit_pre_duration_c - 1;
            when others =>
              null;
          end case;
        end if;

      when ST_START_LOW =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= start_high_duration_c - 1;
          rin.state <= ST_START_HIGH;
        end if;

      when ST_START_HIGH | ST_BIT_POST =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_IDLE;
        end if;

      when ST_BIT_PRE =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= bit_value_duration_c - 1;
          rin.state <= ST_BIT_VAL;
        end if;

      when ST_BIT_VAL =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.timer <= bit_post_duration_c - 1;
          rin.state <= ST_BIT_POST;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    ready_o <= '0';
    cec_o.drain_n <= '1';

    case r.state is
      when ST_RESET | ST_BIT_POST | ST_START_HIGH =>
        null;

      when ST_IDLE =>
        ready_o <= '1';

      when ST_BIT_PRE | ST_START_LOW =>
        cec_o.drain_n <= '0';

      when ST_BIT_VAL =>
        cec_o.drain_n <= r.bit_val;
    end case;
  end process;
  
end architecture;

