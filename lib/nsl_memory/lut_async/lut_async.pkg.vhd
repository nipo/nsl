library ieee;
use ieee.std_logic_1164.all;

package lut_async is

  component lut1 is
    generic (
      contents_c : std_ulogic_vector
      );
    port (
      data_i : in std_ulogic_vector;
      data_o : out std_ulogic
      );
  end component;

end package lut_async;
