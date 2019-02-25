library ieee;
use ieee.std_logic_1164.all;

library signalling;
use signalling.axis.all;

package axis is

  component axis_16l_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_mo   : out signalling.axis.axis_16l_ms;
      p_mi   : in signalling.axis.axis_16l_sm;

      p_done : out std_ulogic
      );
  end component;

  component axis_16l_file_checker is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_so   : out signalling.axis.axis_16l_sm;
      p_si   : in signalling.axis.axis_16l_ms;

      p_done     : out std_ulogic
      );
  end component;

end package axis;
