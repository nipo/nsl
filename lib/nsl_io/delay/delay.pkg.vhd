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
