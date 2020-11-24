library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package ice40 is

  component ice40_opendrain_io_driver is
    port(
      v_i : in nsl_io.io.opendrain;
      v_o : out std_ulogic;
      io_io : inout std_logic
      );
    end component;

end package ice40;
