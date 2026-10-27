library ieee;
use ieee.std_logic_1164.all;

library nsl_math;

-- The delay line is swept from its mark, sampling valid_i once per
-- tap, and each sample is scored by correlating its neighbourhood
-- with kernel_c.  A peaked kernel makes the score drop over a lone
-- bad tap inside an eye and keeps short runs on the side of the eye
-- from winning.
--
-- Correlation is streamed: an accumulator per kernel coefficient
-- collects the contribution of every sample to the score of the tap
-- kernel_c'length / 2 behind it, so no per-tap memory is needed and
-- the number of taps does not need to be known.  The line is swept
-- twice so that every tap is scored with its neighbours across the
-- wrap, and the sweep carries on past the second mark until the
-- plateau of maximal score in progress, if any, closes.  The overrun
-- is bounded by the third mark, reached only when every tap has the
-- same score.
--
-- The center of the last plateau of maximal score is retained,
-- rounded down.  Taps are named by their pulse count from the mark,
-- and this count is not reduced modulo the tap count: the line wraps
-- on its own when the count is applied.
entity input_delay_aligner is
  generic(
    stabilization_cycle_c: integer := 8;
    stabilization_delay_c: integer := 8;
    kernel_c: nsl_math.int_ext.integer_vector := (1, 2, 3, 2, 1)
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

  constant kernel_length_c : integer := kernel_c'length;
  alias x_kernel_c : nsl_math.int_ext.integer_vector(0 to kernel_length_c-1) is kernel_c;
  constant kernel_half_c : integer := kernel_length_c / 2;
  constant score_max_c : integer := nsl_math.int_ext.sum(kernel_c);
  -- Two sweeps and the overrun past the second mark, bounded by a
  -- third mark.
  constant position_max_c : integer := 3 * nsl_math.arith.max(delay_step_count_c, kernel_length_c);

  type score_vector is array (integer range <>) of integer range 0 to score_max_c;

  type state_t is (
    ST_RESET,
    ST_SERDES_RESYNC,
    ST_DELAY_RESYNC,
    ST_DELAY_RESYNC_SHIFT,
    ST_STABILITY_WAIT,
    ST_STABILITY_EVAL,
    ST_ACCUMULATE,
    ST_EVALUATE,
    ST_DELAY_STEP,
    ST_DELAY_STEPPED,
    ST_DELAY_SCANNED,
    ST_SERDES_STEP,
    ST_DELAY_ALIGN,
    ST_DELAY_ALIGN_SHIFT,
    ST_DELAY_APPLY,
    ST_VERIFY_WAIT,
    ST_VERIFY,
    ST_LOCKED
    );

  type regs_t is
  record
    state: state_t;
    stabilization_timeout: integer range 0 to stabilization_max_c-1;
    sample: boolean;
    backlog: score_vector(0 to kernel_length_c-1);
    score_max: integer range 0 to score_max_c;
    contiguous, odd: boolean;
    index, center: integer range 0 to position_max_c;
    marks: integer range 0 to 3;
  end record;

  signal r, rin: regs_t;

begin

  assert kernel_length_c > 0 and nsl_math.int_ext.min(kernel_c) >= 0 and score_max_c > 0
    report "kernel_c must be a non-empty, non-negative, non-null vector"
    severity failure;

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
    variable marks: integer range 0 to 4;
  begin
    rin <= r;

    if delay_mark_i = '1' then
      marks := r.marks + 1;
    else
      marks := r.marks;
    end if;

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
          rin.stabilization_timeout <= stabilization_delay_c - 1;
          rin.backlog <= (others => 0);
          rin.score_max <= 0;
          rin.contiguous <= false;
          rin.odd <= false;
          rin.index <= 0;
          rin.center <= 0;
          rin.marks <= 0;
        else
          rin.state <= ST_DELAY_RESYNC_SHIFT;
        end if;

      when ST_DELAY_RESYNC_SHIFT =>
        rin.state <= ST_DELAY_RESYNC;

      when ST_STABILITY_WAIT =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if r.stabilization_timeout = 0 then
          rin.state <= ST_STABILITY_EVAL;
          rin.stabilization_timeout <= stabilization_cycle_c - 1;
        end if;

      when ST_STABILITY_EVAL =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if valid_i = '0' then
          rin.sample <= false;
          rin.state <= ST_ACCUMULATE;
        elsif r.stabilization_timeout = 0 then
          rin.sample <= true;
          rin.state <= ST_ACCUMULATE;
        end if;

      when ST_ACCUMULATE =>
        rin.state <= ST_EVALUATE;
        if r.sample then
          for i in 0 to kernel_length_c-1
          loop
            rin.backlog(i) <= r.backlog(i) + x_kernel_c(i);
          end loop;
        end if;

      when ST_EVALUATE =>
        rin.state <= ST_DELAY_STEP;
        rin.index <= r.index + 1;
        rin.backlog(0 to kernel_length_c-2) <= r.backlog(1 to kernel_length_c-1);
        rin.backlog(kernel_length_c-1) <= 0;

        -- Scores of the first sweep's leading taps lack their
        -- neighbours across the wrap.  They are scored again,
        -- complete, later on.
        if r.index < kernel_length_c - 1 then
          rin.contiguous <= false;
        elsif r.backlog(0) > r.score_max or (r.backlog(0) = r.score_max and not r.contiguous) then
          rin.score_max <= r.backlog(0);
          rin.center <= r.index - kernel_half_c;
          rin.contiguous <= true;
          rin.odd <= false;
        elsif r.backlog(0) = r.score_max then
          rin.odd <= not r.odd;
          if r.odd then
            rin.center <= r.center + 1;
          end if;
        else
          rin.contiguous <= false;
        end if;

      when ST_DELAY_STEP =>
        rin.state <= ST_DELAY_STEPPED;

      when ST_DELAY_STEPPED =>
        rin.state <= ST_STABILITY_WAIT;
        rin.stabilization_timeout <= stabilization_delay_c - 1;
        if marks <= 3 then
          rin.marks <= marks;
        end if;

        -- Every tap is scored complete once two sweeps are done and
        -- the stream is long enough for the kernel, even on a line
        -- with fewer taps than the kernel.  Only a plateau that may
        -- get retained is worth carrying the sweep further for.
        if marks >= 3
          and r.index >= 3 * (kernel_length_c - 1) then
          rin.state <= ST_DELAY_SCANNED;
        elsif marks >= 2
          and r.index >= 2 * (kernel_length_c - 1)
          and not (r.contiguous and r.score_max /= 0) then
          rin.state <= ST_DELAY_SCANNED;
        end if;

      when ST_DELAY_SCANNED =>
        -- However narrow the eye, any valid tap is better than a
        -- serdes slip.
        if r.score_max = 0 then
          rin.state <= ST_SERDES_STEP;
        else
          rin.state <= ST_DELAY_ALIGN;
        end if;

      when ST_SERDES_STEP =>
        rin.state <= ST_DELAY_RESYNC;

      when ST_DELAY_ALIGN =>
        if delay_mark_i = '1' then
          rin.state <= ST_DELAY_APPLY;
        else
          rin.state <= ST_DELAY_ALIGN_SHIFT;
        end if;

      when ST_DELAY_ALIGN_SHIFT =>
        rin.state <= ST_DELAY_ALIGN;

      when ST_DELAY_APPLY =>
        if r.center = 0 then
          rin.state <= ST_VERIFY_WAIT;
          rin.stabilization_timeout <= stabilization_delay_c - 1;
        else
          rin.center <= r.center - 1;
        end if;

      when ST_VERIFY_WAIT =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if r.stabilization_timeout = 0 then
          rin.state <= ST_VERIFY;
          rin.stabilization_timeout <= stabilization_cycle_c - 1;
        end if;

      when ST_VERIFY =>
        rin.stabilization_timeout <= (r.stabilization_timeout - 1) mod stabilization_max_c;
        if valid_i = '0' then
          rin.state <= ST_SERDES_STEP;
        elsif r.stabilization_timeout = 0 then
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
      when ST_SERDES_RESYNC | ST_SERDES_STEP =>
        serdes_shift_o <= '1';

      -- Mark is only looked at the cycle after a shift, so that the
      -- line stops on it rather than one tap past.
      when ST_DELAY_RESYNC_SHIFT | ST_DELAY_STEP | ST_DELAY_ALIGN_SHIFT =>
        delay_shift_o <= '1';

      when ST_DELAY_APPLY =>
        if r.center /= 0 then
          delay_shift_o <= '1';
        end if;

      when ST_LOCKED =>
        ready_o <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture;
