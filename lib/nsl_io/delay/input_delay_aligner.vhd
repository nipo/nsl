library ieee;
use ieee.std_logic_1164.all;

library nsl_math;

entity input_delay_aligner is
  generic(
    stabilization_cycle_c: integer := 8;
    stabilization_delay_c: integer := 8
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    delay_shift_o : out std_ulogic;
    delay_mark_i : in std_ulogic := '1';
    serdes_shift_o : out std_ulogic;
    serdes_mark_i : in std_ulogic := '1';

    restart_i: in std_ulogic := '0';
    valid_i : in std_ulogic;
    ready_o: out std_ulogic
    );
end entity;

architecture beh of input_delay_aligner is

  constant delay_step_count_c : integer := 256;
  constant stabilization_max_c : integer := nsl_math.arith.align_up(nsl_math.arith.max(stabilization_cycle_c, stabilization_delay_c));
  
  type state_t is (
    ST_RESET,
    ST_SERDES_RESYNC,
    ST_DELAY_RESYNC,
    ST_STABILITY_WAIT,
    ST_STABILITY_EVAL,
    ST_DELAY_STEP,
    ST_DELAY_SCANNED,
    ST_SERDES_STEP,
    ST_DELAY_ALIGN,
    ST_DELAY_APPLY,
    ST_LOCKED
    );

  type regs_t is
  record
    delay_valid_first, delay_valid_last, delay_value: integer range 0 to delay_step_count_c-1;
    had_valid: boolean;
    stabilization_timeout: integer range 0 to stabilization_max_c-1;
    state: state_t;
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

  transition: process(r, delay_mark_i, serdes_mark_i, valid_i, restart_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_SERDES_RESYNC;

      when ST_SERDES_RESYNC =>
        if serdes_mark_i = '1' then
          rin.state <= ST_DELAY_RESYNC;
        end if;

      when ST_DELAY_RESYNC =>
        if delay_mark_i = '1' then
          rin.state <= ST_STABILITY_WAIT;
          rin.delay_valid_first <= 0;
          rin.delay_valid_last <= 0;
          rin.had_valid <= false;
          rin.stabilization_timeout <= stabilization_delay_c - 1;
        end if;

      when ST_STABILITY_WAIT =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if r.stabilization_timeout = 0 then
          rin.state <= ST_STABILITY_EVAL;
          rin.stabilization_timeout <= stabilization_cycle_c - 1;
        end if;

      when ST_STABILITY_EVAL =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if valid_i = '0' then
          rin.delay_value <= (r.delay_value + 1) mod delay_step_count_c;
          rin.state <= ST_DELAY_STEP;
        elsif r.stabilization_timeout = 0 then
          rin.had_valid <= true;
          if not r.had_valid then
            rin.delay_valid_first <= r.delay_value;
          end if;
          rin.delay_valid_last <= r.delay_value;
        
          rin.delay_value <= (r.delay_value + 1) mod delay_step_count_c;
          rin.state <= ST_DELAY_STEP;
        end if;

      when ST_DELAY_STEP =>
        if delay_mark_i = '1' then
          rin.state <= ST_DELAY_SCANNED;
        else
          rin.state <= ST_STABILITY_WAIT;
          rin.stabilization_timeout <= stabilization_delay_c - 1;
        end if;

      when ST_SERDES_STEP =>
        rin.state <= ST_STABILITY_WAIT;
        rin.delay_valid_first <= 0;
        rin.delay_valid_last <= 0;
        rin.delay_value <= 0;
        rin.had_valid <= false;
        rin.stabilization_timeout <= stabilization_delay_c - 1;
        
      when ST_DELAY_SCANNED =>
        if not r.had_valid then
          rin.state <= ST_SERDES_STEP;
        else
          rin.state <= ST_DELAY_ALIGN;
        end if;
        
      when ST_DELAY_ALIGN =>
        if delay_mark_i = '1' then
          rin.state <= ST_DELAY_APPLY;
          rin.delay_value <= (r.delay_valid_first + r.delay_valid_last) / 2;
        end if;

      when ST_DELAY_APPLY =>
        rin.delay_value <= (r.delay_value - 1) mod delay_step_count_c;
        if r.delay_value = 0 then
          rin.state <= ST_LOCKED;
        end if;

      when ST_LOCKED =>
        if restart_i = '1' then
          rin.state <= ST_RESET;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    delay_shift_o <= '0';
    serdes_shift_o <= '0';
    ready_o <= '0';

    case r.state is
      when ST_RESET | ST_DELAY_SCANNED | ST_STABILITY_WAIT | ST_STABILITY_EVAL =>
        null;

      when ST_SERDES_RESYNC | ST_SERDES_STEP =>
        serdes_shift_o <= '1';

      when ST_DELAY_ALIGN | ST_DELAY_RESYNC | ST_DELAY_APPLY | ST_DELAY_STEP =>
        delay_shift_o <= '1';

      when ST_LOCKED =>
        ready_o <= '1';
    end case;
  end process;

end architecture;
