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

end package delay;
