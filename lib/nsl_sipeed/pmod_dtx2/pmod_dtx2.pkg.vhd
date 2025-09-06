library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_digilent, nsl_indication;

package pmod_dtx2 is
  
  component pmod_dtx2_driver is
    generic(
      clock_i_hz_c: integer;
      blink_rate_hz_c: integer := 100
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;
      
      value_i: in nsl_indication.seven_segment.seven_segment_vector(0 to 1);
      pmod_io : inout nsl_digilent.pmod.pmod_double_t
      );
  end component;
  
  component pmod_dtx2_hex is
    generic(
      clock_i_hz_c: integer;
      blink_rate_hz_c: integer := 100
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      value_i: in unsigned(7 downto 0);
      pmod_io : inout nsl_digilent.pmod.pmod_double_t
      );
  end component;
  
  component pmod_dtx2_characters is
    generic(
      clock_i_hz_c: integer;
      blink_rate_hz_c: integer := 100
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      character_i: in string(1 to 2);
      pmod_io : inout nsl_digilent.pmod.pmod_double_t
      );
  end component;

end package pmod_dtx2;
