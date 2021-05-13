library ieee;
use ieee.std_logic_1164.all;

library nsl_math;
use nsl_math.fixed.all;

package gaussian is

  -- This a gaussian filter approximation with box filters.
  component gaussian_box_ufixed is
    generic(
      -- = FS / bitrate
      symbol_sample_count_c : integer;
      -- Bandwidth-time product
      bt_c : real
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in ufixed;
      out_o : out ufixed
      );
  end component;

  -- This a gaussian filter approximation with RC filters.
  component gaussian_rc_ufixed is
    generic(
      -- = FS / bitrate
      symbol_sample_count_c : integer;
      -- Bandwidth-time product
      bt_c : real
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in ufixed;
      out_o : out ufixed
      );
  end component;

  -- Meta component for using one of the two previous components
  component gaussian_ufixed is
    generic(
      -- = FS / bitrate
      symbol_sample_count_c : integer;
      -- Bandwidth-time product
      bt_c : real;
      -- "box" or "rc"
      approximation_method_c : string := "box"
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in ufixed;
      out_o : out ufixed
      );
  end component;

end package;
