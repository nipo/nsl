library ieee;
use ieee.std_logic_1164.all;

library nsl_axi;

package axis is

  component axis_16l_file_reader is
    generic(
      filename: string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      m_o   : out nsl_axi.stream.axis_16l_ms;
      m_i   : in nsl_axi.stream.axis_16l_sm;

      done_o : out std_ulogic
      );
  end component;

  component axis_16l_file_checker is
    generic(
      filename: string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      s_o   : out nsl_axi.stream.axis_16l_sm;
      s_i   : in nsl_axi.stream.axis_16l_ms;

      done_o     : out std_ulogic
      );
  end component;

end package axis;
