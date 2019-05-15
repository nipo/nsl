library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ioext is

  component ioext_sync_output is
    generic(
      p_clk_rate : natural;
      p_sr_clk_rate : natural
      );
    port(
      p_resetn    : in std_ulogic;
      p_clk       : in std_ulogic;

      p_data      : in std_ulogic_vector(7 downto 0);
      p_done      : out std_ulogic;

      p_sr_d      : out std_ulogic;
      p_sr_clk    : out std_ulogic;
      p_sr_strobe : out std_ulogic
      );
  end component;

end package ioext;
