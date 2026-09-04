library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use work.timestamp.all;
use nsl_math.fixed.all;

-- Clock discipline, split from the synchronization protocols: a
-- source measures how far the local clock is from a reference and
-- streams offset measurements; the servo turns them into a frequency
-- correction; a driver applies the correction to whatever steers the
-- local frequency.
--
-- Sources speak the currency of nsl_time.skew.skew_measurer: a
-- strobe qualifying a timestamp_nanosecond_offset_t, local time
-- minus reference, positive when the local clock is ahead.  A PTP
-- client, a PPS comparator or any custom protocol produce the same
-- stream.
--
-- Sinks take the servo's frequency offset, in signed parts per
-- billion, positive to speed the local clock up:
-- discipline_clock_driver computes the per-cycle increment of
-- nsl_time.clock.clock_adjustable, discipline_dac_driver computes
-- the code of a DAC pulling a VCTCXO.
--
-- Absolute time steps do not go through the servo: the source
-- requests them straight at the clock (clock_adjustable set ports),
-- and the servo's integrator, which estimates frequency error, stays
-- valid across a phase step.
package discipline is

  subtype frequency_ppb_t is signed(23 downto 0);

  -- Proportional-integral servo.  Each qualified offset adds
  -- contributions scaled by right shifts: proportional
  -- -(offset / 2**kp_l2_c) and integral accumulation of
  -- -(offset / 2**ki_l2_c), both in parts per billion per nanosecond
  -- of offset.  The gains fold the measurement period in: they are
  -- tuned for a given source rate.  The output is clamped to
  -- +/- freq_clamp_ppb_c; the integrator saturates at the clamp so
  -- it does not wind up.  clear_i empties the integrator and zeroes
  -- the output.
  component discipline_pi_servo is
    generic(
      kp_l2_c : natural := 2;
      ki_l2_c : natural := 6;
      freq_clamp_ppb_c : natural := 100000
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      clear_i : in std_ulogic := '0';

      offset_i : in timestamp_nanosecond_offset_t;
      offset_valid_i : in std_ulogic;

      freq_offset_ppb_o : out frequency_ppb_t
      );
  end component;

  -- Computes the sub-nanosecond increment of
  -- nsl_time.clock.clock_adjustable running at clock_i_hz_c:
  -- (1e9 / clock_i_hz_c) * (1 + freq_offset_ppb_i * 1e-9)
  -- nanoseconds per cycle, registered.  The output range is taken
  -- from the actual signal, which must hold the nominal increment
  -- with headroom for the clamp of the servo in front.
  component discipline_clock_driver is
    generic(
      clock_i_hz_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      freq_offset_ppb_i : in frequency_ppb_t;

      sub_nanosecond_inc_o : out ufixed
      );
  end component;

  -- Computes the code of a DAC pulling a VCTCXO whose frequency
  -- swings by full_scale_ppb_c across the code range, centered on
  -- midscale: mid + freq_offset_ppb_i * 2**dac_width_c /
  -- full_scale_ppb_c, clamped to the rails.  invert_c is for
  -- oscillators that slow down as the code grows.  changed_o pulses
  -- when dac_o takes a new value, for the transport to push it.
  component discipline_dac_driver is
    generic(
      dac_width_c : natural;
      full_scale_ppb_c : natural;
      invert_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      freq_offset_ppb_i : in frequency_ppb_t;

      dac_o : out unsigned(dac_width_c-1 downto 0);
      changed_o : out std_ulogic
      );
  end component;

end package;
