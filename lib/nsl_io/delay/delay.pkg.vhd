library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

package delay is

  component output_delay_fixed is
    generic(
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  component input_delay_fixed is
    generic(
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  component output_delay_variable is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      mark_o : out std_ulogic;
      shift_i : in std_ulogic;

      data_i : in std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  -- Calibration reference the variable delay lines of some families
  -- need before their taps mean anything.  One instance serves every
  -- delay line in a design; where a family needs none, ready_o is
  -- asserted and nothing is built.
  --
  -- clock_i is the reference frequency the delay lines were told to
  -- expect, which is a property of the family rather than of the
  -- design.
  component delay_reference is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      ready_o : out std_ulogic
      );
  end component;

  -- Input delay line whose length is walked a tap at a time.
  --
  -- A pulse on shift_i makes the line one tap longer, and the line
  -- wraps to its shortest tap past the longest one it carries.  mark_o
  -- says the line is at that shortest tap, tap zero, which is the only
  -- position a design can name without knowing how many taps a family
  -- gives it: n pulses from the mark leave the line at tap n.
  --
  -- How long a tap is, and how many there are, belong to the family.  A
  -- design that needs a known position walks to the mark and counts
  -- from there.
  component input_delay_variable is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      mark_o : out std_ulogic;
      shift_i : in std_ulogic;

      data_i : in std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  component input_delay_variable_sdr is
    port(
      clock_i : in std_ulogic;
      bit_clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      mark_o : out std_ulogic;
      shift_i : in std_ulogic;

      data_i : in std_ulogic;
      data_o : out std_ulogic
      );
  end component;

  -- Iterates over the possible delay and bit slip possibilities and
  -- gets the first good match match.
  -- There may be no serdes shift or no delay shift. In such case, leave defaut
  -- assignments.
  component input_delay_aligner is
    generic(
      -- Word count to wait between changing parameters and evaluating whether
      -- data decode is correct.
      stabilization_delay_c: integer := 8;
      -- Contiguous word count to assert validity for
      stabilization_cycle_c: integer := 8
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      delay_shift_o : out std_ulogic;
      delay_mark_i : in std_ulogic := '1';
      serdes_shift_o : out std_ulogic;
      serdes_mark_i : in std_ulogic := '1';

      -- While ready_o = '1', asserting this input restarts training
      restart_i: in std_ulogic := '0';
      -- Tells the aligner that data input is correct
      valid_i : in std_ulogic;
      -- Training done
      ready_o: out std_ulogic
      );
  end component;

  -- Iterates over all possible delay and bit slip possibilities and
  -- gets the best match.
  -- Worst case scenario, the aligner iterates twice over all 
  -- the delay and bit slip possibilities
  component input_delay_aligner_slow is
    generic(
      -- Word count to wait between changing parameters and evaluating whether
      -- data decode is correct.
      stabilization_delay_c: integer := 8;
      -- Contiguous word count to assert validity for
      stabilization_cycle_c: integer := 8
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      delay_shift_o : out std_ulogic;
      delay_mark_i : in std_ulogic := '1';
      serdes_shift_o : out std_ulogic;
      serdes_mark_i : in std_ulogic := '1';

      -- While ready_o = '1', asserting this input restarts training
      restart_i: in std_ulogic := '0';
      -- Tells the aligner that data input is correct
      valid_i : in std_ulogic;
      -- Training done
      ready_o: out std_ulogic
      );
  end component;

  component output_bus_delay_fixed is
    generic(
      width_c : natural;
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic_vector(0 to width_c-1);
      data_o : out std_ulogic_vector(0 to width_c-1)
      );
  end component;

  component input_bus_delay_fixed is
    generic(
      width_c : natural;
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic_vector(0 to width_c-1);
      data_o : out std_ulogic_vector(0 to width_c-1)
      );
  end component;

end package delay;
