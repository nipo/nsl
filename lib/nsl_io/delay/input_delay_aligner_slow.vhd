library ieee;
use ieee.std_logic_1164.all;

library nsl_math;

entity input_delay_aligner_slow is
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

architecture beh of input_delay_aligner_slow is

  constant delay_step_count_c  : integer := 256;
  constant serdes_step_count_c : integer := 10;
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
    ST_ALL_SCANNED,
    ST_APPLY_SERDES,
    ST_APPLY_SERDES_WAIT,
    ST_APPLY_DELAY,
    ST_APPLY_DELAY_WAIT,
    ST_VERIFY,
    ST_LOCKED
    );

  type regs_t is
  record
    delay_valid_first, delay_valid_last, delay_value: integer range 0 to delay_step_count_c-1;
    had_valid: boolean;
    stabilization_timeout: integer range 0 to stabilization_max_c-1;
    state: state_t;
    verify_timeout: integer range 0 to 31;
    serdes_steps_done: integer range 0 to serdes_step_count_c-1;
    best_width: integer range 0 to delay_step_count_c;
    best_serdes_count: integer range 0 to serdes_step_count_c-1;
    best_delay_center: integer range 0 to delay_step_count_c-1;
    apply_count: integer range 0 to delay_step_count_c-1;
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
        rin.best_width <= 0;
        rin.serdes_steps_done <= 0;

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
          rin.delay_value <= 0;
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

      when ST_DELAY_SCANNED =>
        if r.had_valid and
           (r.delay_valid_last - r.delay_valid_first + 1) > r.best_width then
          rin.best_width <= r.delay_valid_last - r.delay_valid_first + 1;
          rin.best_serdes_count <= r.serdes_steps_done;
          rin.best_delay_center <= (r.delay_valid_first + r.delay_valid_last) / 2;
        end if;
        if r.serdes_steps_done = serdes_step_count_c - 1 then
          rin.state <= ST_ALL_SCANNED;
        else
          rin.state <= ST_SERDES_STEP;
        end if;

      when ST_SERDES_STEP =>
        rin.serdes_steps_done     <= r.serdes_steps_done + 1;
        rin.delay_valid_first     <= 0;
        rin.delay_valid_last      <= 0;
        rin.had_valid             <= false;
        rin.delay_value           <= 0;
        rin.stabilization_timeout <= stabilization_delay_c - 1;
        rin.state                 <= ST_STABILITY_WAIT;

      when ST_ALL_SCANNED =>
        if r.best_width = 0 then
          rin.state <= ST_RESET;
        else
          -- Navigate forward from the current SERDES position (9 steps past initial)
          -- to best_serdes_count steps past initial: need (best_serdes_count+1) mod 10 steps.
          rin.apply_count <= (r.best_serdes_count + 1) mod serdes_step_count_c;
          rin.state       <= ST_APPLY_SERDES;
        end if;

      when ST_APPLY_SERDES =>
        -- If no steps remain, move on to the delay apply phase.
        -- Delay is already at tap_max-1 (delay_value=0 reference) from the last scan wrap.
        if r.apply_count = 0 then
          rin.apply_count <= r.best_delay_center;
          rin.state       <= ST_APPLY_DELAY;
        else
          -- Pulse shift this cycle (see moore), then wait before the next one.
          rin.apply_count           <= r.apply_count - 1;
          rin.stabilization_timeout <= stabilization_delay_c - 1;
          rin.state                 <= ST_APPLY_SERDES_WAIT;
        end if;

      when ST_APPLY_SERDES_WAIT =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if r.stabilization_timeout = 0 then
          rin.state <= ST_APPLY_SERDES;
        end if;

      when ST_APPLY_DELAY =>
        if r.apply_count = 0 then
          rin.state          <= ST_VERIFY;
          rin.verify_timeout <= 31;
        else
          rin.apply_count           <= r.apply_count - 1;
          rin.stabilization_timeout <= stabilization_delay_c - 1;
          rin.state                 <= ST_APPLY_DELAY_WAIT;
        end if;

      when ST_APPLY_DELAY_WAIT =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if r.stabilization_timeout = 0 then
          rin.state <= ST_APPLY_DELAY;
        end if;

      when ST_VERIFY =>
        rin.verify_timeout <= (r.verify_timeout - 1) mod 32;
        if r.verify_timeout = 0 then
          if valid_i = '1' then
            rin.state <= ST_LOCKED;
          else
            rin.state <= ST_RESET;
          end if;
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
      when ST_RESET | ST_DELAY_SCANNED | ST_STABILITY_WAIT | ST_STABILITY_EVAL
         | ST_ALL_SCANNED | ST_VERIFY
         | ST_APPLY_SERDES_WAIT | ST_APPLY_DELAY_WAIT =>
        null;

      when ST_SERDES_RESYNC | ST_SERDES_STEP =>
        serdes_shift_o <= '1';

      when ST_APPLY_SERDES =>
        -- Shift only when there are steps remaining; apply_count=0 is the exit condition.
        if r.apply_count /= 0 then
          serdes_shift_o <= '1';
        end if;

      when ST_DELAY_RESYNC | ST_DELAY_STEP =>
        delay_shift_o <= '1';

      when ST_APPLY_DELAY =>
        if r.apply_count /= 0 then
          delay_shift_o <= '1';
        end if;

      when ST_LOCKED =>
        ready_o <= '1';
    end case;
  end process;

end architecture;
