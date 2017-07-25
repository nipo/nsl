library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package util is

  component baudrate_generator is
    generic(
      p_clk_rate : natural;
      rate_lsb   : natural := 8;
      rate_msb   : natural := 27
      );
    port(
      p_clk      : in std_ulogic;
      p_resetn   : in std_ulogic;
      p_rate     : in unsigned(rate_msb downto rate_lsb);
      p_tick     : out std_ulogic
      );
  end component;

end package util;
