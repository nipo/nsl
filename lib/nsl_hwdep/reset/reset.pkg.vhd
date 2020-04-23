library ieee;
use ieee.std_logic_1164.all;

package reset is

  component reset_at_startup is
    port(
      clock_i       : in std_ulogic;
      reset_n_o    : out std_ulogic
      );
  end component;

end package reset;
