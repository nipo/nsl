library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library nsl_math;
use nsl_math.fixed.all;

entity async_recovery is
  generic(
    clock_i_hz_c : natural;
    tick_skip_max_c : natural := 2;
    tick_i_hz_c : natural;
    tick_o_hz_c : natural;
    target_ppm_c : natural
    );
  port (
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;
    tick_valid_i : in std_ulogic := '1';
    tick_i : in std_ulogic;
    tick_o : out std_ulogic
    );

begin

  assert clock_i_hz_c > tick_i_hz_c * 2
    report "Block clock must be above Nyquist limit for sampling input tick"
    severity failure;

  assert clock_i_hz_c > tick_o_hz_c * 2
    report "Block clock must be above Nyquist limit for generating output tick"
    severity failure;
  
end async_recovery;

architecture rtl of async_recovery is

  constant clock_i_hz : real := real(clock_i_hz_c);
  constant tick_i_hz : real := real(tick_i_hz_c);

  -- Input and output nominal tick period, in clock_i cycles
  constant tick_o_period_nom : real := real(clock_i_hz) / real(tick_o_hz_c);
  constant tick_i_period_nom : real := real(clock_i_hz) / real(tick_i_hz_c);

  -- Fractional part of lowpass filter to reach target PPM
  constant lowpass_frac_w : integer := integer(log2(1.0e6 / real(target_ppm_c)) + 1.0);

  -- Integer part of input counter/accumulator
  constant tick_i_acc_max : real := tick_i_period_nom + 1.0;
  constant tick_i_acc_int_length : integer := integer(ceil(log2(tick_i_acc_max) + 1.0));

  -- Integer part of I/O counter/accumulator
  constant tick_io_acc_max : real := tick_o_period_nom + tick_i_period_nom;
  constant tick_io_acc_int_length : integer := integer(ceil(log2(tick_io_acc_max) + 1.0));

  subtype i_ctr_t is ufixed(tick_i_acc_int_length downto -lowpass_frac_w-1);
  subtype io_ctr_t is ufixed(tick_io_acc_int_length downto -lowpass_frac_w);

  function to_i_ctr(value : real) return ufixed
  is
  begin
    return to_ufixed(value => value,
                     left => i_ctr_t'left,
                     right => i_ctr_t'right);
  end function;

  function to_io_ctr(value : real) return ufixed
  is
  begin
    return to_ufixed(value => value,
                     left => io_ctr_t'left,
                     right => io_ctr_t'right);
  end function;

  constant tick_o_period_uf : io_ctr_t := to_io_ctr(tick_i_period_nom / tick_o_period_nom);
  constant tick_i_period_uf : i_ctr_t := to_i_ctr(tick_i_period_nom);
  constant tick_i_timeout_uf : i_ctr_t := to_i_ctr(tick_i_period_nom + 1.0);
  
  type regs_t is
  record
    skip_count : natural range 0 to tick_skip_max_c;
    tick_i_acc : i_ctr_t;
    tick_i_acc_lp : i_ctr_t;
    tick_i_valid : boolean;

    tick_i_period_measured : io_ctr_t;
    tick_io_acc : io_ctr_t;
    tick_o : boolean;
  end record;

  signal r, rin : regs_t;

  signal tick_i_acc, tick_i_acc_lp, tick_i_period_measured, tick_io_acc : real;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.skip_count <= 0;
      r.tick_i_acc <= to_i_ctr(0.0);
      r.tick_i_acc_lp <= tick_i_period_uf;
      r.tick_io_acc <= to_io_ctr(0.0);
      r.tick_i_valid <= false;
    end if;
  end process;

  transition: process(r, tick_valid_i, tick_i) is
  begin
    rin <= r;

    -- Tick_o is generated from measured tick_i period gone through
    -- lowpass and nominal tick_o period
    if r.tick_io_acc >= r.tick_i_period_measured then
      rin.tick_io_acc <= r.tick_io_acc + tick_o_period_uf - r.tick_i_period_measured;
      rin.tick_o <= true;
    else
      rin.tick_io_acc <= r.tick_io_acc + tick_o_period_uf;
      rin.tick_o <= false;
    end if;

    -- Tick_i measurement only happens when we get a valid cycle
    if tick_valid_i = '0' then
      rin.tick_i_valid <= false;
    end if;

    if r.skip_count >= tick_skip_max_c then
      rin.tick_i_valid <= false;
    end if;

    if not r.tick_i_valid then
      if tick_i = '1' then
        rin.tick_i_valid <= true;
        rin.tick_i_acc <= to_i_ctr(1.0);
        rin.skip_count <= 0;
      end if;
    else
      if tick_i = '1' then
        rin.skip_count <= 0;
        rin.tick_i_acc_lp <= r.tick_i_acc_lp
                             + shra((r.tick_i_acc - r.tick_i_acc_lp), lowpass_frac_w);
        rin.tick_i_acc <= to_i_ctr(1.0);
      else
        if r.tick_i_acc >= tick_i_timeout_uf then
          rin.skip_count <= r.skip_count + 1;
          rin.tick_i_acc <= r.tick_i_acc + to_i_ctr(1.0) - r.tick_i_acc_lp;
        else
          rin.tick_i_acc <= r.tick_i_acc + to_i_ctr(1.0);
        end if;
      end if;
    end if;

    -- Extract lowpassed tick_i period
    rin.tick_i_period_measured <= resize(value => r.tick_i_acc_lp,
                                         left => r.tick_i_period_measured'left,
                                         right => r.tick_i_period_measured'right);
  end process;

  tick_o <= '1' when r.tick_o else '0';
  tick_i_acc <= to_real(r.tick_i_acc);
  tick_i_acc_lp <= to_real(r.tick_i_acc_lp);
  tick_i_period_measured <= to_real(r.tick_i_period_measured);
  tick_io_acc <= to_real(r.tick_io_acc);
  
end rtl;
