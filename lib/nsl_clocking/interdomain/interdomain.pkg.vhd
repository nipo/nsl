library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

-- Inter-clock-domain utilities
package interdomain is

  -- Enforces max skew for the whole bus will not be above the fastest
  -- clock cycle time. Mostly suited for gray-coded data.
  --
  -- If not gray-coded, this register may wait for resynchronized data
  -- to be stable for /stable_count_c/ cycles before forwarding to the
  -- output. If stable_count_c = 0, this is disabled.
  component interdomain_reg is
    generic(
      stable_count_c : natural               := 0;
      cycle_count_c  : natural range 2 to 40 := 2;
      data_width_c   : integer
      );
    port(
      clock_i : in  std_ulogic;
      data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o  : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- Makes a 1-stepped counter cross a clock region. Input/output can
  -- optionally be gray-encoded. If not, they'll internally be
  -- converted.
  --
  -- decode_stage_count allows for some timing relaxation of gray decoding
  -- state. It is unused if output is gray-coded.
  --
  -- Total latency:
  -- 1 * in_clock period
  --  + inter-clock jitter
  --  + (cycle_count_c + decode_stage_count) * out_clock period
  component interdomain_counter is
    generic(
      cycle_count_c        : natural := 2;
      data_width_c         : integer;
      decode_stage_count_c : natural := 1;
      input_is_gray_c      : boolean := false;
      output_is_gray_c     : boolean := false
      );
    port(
      clock_in_i  : in  std_ulogic;
      clock_out_i : in  std_ulogic;
      data_i      : in  unsigned(data_width_c-1 downto 0);
      data_o      : out unsigned(data_width_c-1 downto 0)
      );
  end component;

  -- Clocks input data to a register (clock is from the input domain),
  -- and ignores all timing constraints on the output side. This is
  -- mostly for configuration data that is not supposed to change
  -- frequently.
  component interdomain_static_reg is
    generic(
      data_width_c : integer
      );
    port(
      input_clock_i : in  std_ulogic;
      data_i        : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o        : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- This is a two word data fifo with two clocks.  It is implemented
  -- with resynchronized acknowledge signals.  A flit takes at least 3
  -- cycles of the slowest clock to go through.
  component interdomain_fifo_slice
    generic(
      data_width_c   : integer
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic_vector(0 to 1);

      out_data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic;

      in_data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic
      );
  end component;

  -- Resynchronizer for mesochronous data buses. Frequency for both
  -- clocks must be exactly the same, relative phase is assumed to be
  -- unknown and unimportant, but not changing (or frequencies would
  -- not be the same anyway).
  --
  -- Component must be reset if glitches happen on any of its clocks.
  --
  -- Validity output is meaningful after at least one cycle of the
  -- output clock. It asserts for validity of data bus, i.e. that this
  -- value happened on the input bus while not reset.
  component interdomain_mesochronous_resync is
    generic(
      data_width_c   : integer
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i   : in std_ulogic_vector(0 to 1);

      data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o  : out std_ulogic_vector(data_width_c-1 downto 0);
      valid_o : out std_ulogic
      );
  end component;

  -- Takes a tick in an input domain, and translate it to a tick in
  -- output domain.  Can reach at most lowest of half input clock
  -- frequency and half of output clock frequency.
  component interdomain_tick is
    port(
      input_clock_i : in  std_ulogic;
      output_clock_i : in  std_ulogic;
      input_reset_n_i : in std_ulogic;
      tick_i : in  std_ulogic;
      tick_o : out std_ulogic
      );
  end component;

  -- Estimates a clock rate and discriminates among multiple fixed
  -- possible clock rates.
  component clock_rate_estimator is
    generic(
      -- Reference clock
      clock_hz_c : real;
      -- Possible clock rates to discriminate for.
      -- Will be used as a 0-based ascending order vector.
      rate_choice_c : nsl_math.real_ext.real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;
      measured_clock_i: in std_ulogic;
      -- Index of rate in rate_choice_c above. Always 0-based even if
      -- rate_choice_c is not ascending or not with 'low = 0.
      rate_index_o: out unsigned
      );
  end component;

  -- Measures a clock against another clock. Updates 2 ** update_hz_l2_c times
  -- per second. It is up to the user to supply a rate_hz_o signal big enough
  -- not to have overflow on the measured value.
  component clock_rate_measurer is
    generic(
      clock_i_hz_c : integer;
      update_hz_l2_c : integer := 0
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;
      measured_clock_i: in std_ulogic;
      rate_hz_o: out unsigned
      );
  end component;

end package interdomain;
