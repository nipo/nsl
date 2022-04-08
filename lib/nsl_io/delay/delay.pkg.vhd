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

  -- Iterates over all possible delay and bit slip possibilities and
  -- gets the best match.
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

  component output_bus_delay_fixed is
    generic(
      width_c : natural;
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic_vector(0 to width_c);
      data_o : out std_ulogic_vector(0 to width_c)
      );
  end component;

  component input_bus_delay_fixed is
    generic(
      width_c : natural;
      delay_ps_c: integer;
      is_ddr_c: boolean := true
      );
    port(
      data_i : in std_ulogic_vector(0 to width_c);
      data_o : out std_ulogic_vector(0 to width_c)
      );
  end component;

end package delay;
