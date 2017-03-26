library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.types.all;

package swd is

  component swd_master is
    port(
      p_reset_n   : in  std_ulogic;
      p_clk       : in  std_ulogic;

      p_rsp       : out std_ulogic_vector(7 downto 0);
      p_rsp_val   : out std_ulogic;
      p_rsp_ack   : in  std_ulogic;

      p_cmd       : in  std_ulogic_vector(7 downto 0);
      p_cmd_val   : in  std_ulogic;
      p_cmd_ack   : out std_ulogic;

      p_swclk     : out std_ulogic;
      p_swdio_o   : out std_ulogic;
      p_swdio_i   : in std_ulogic;
      p_swdio_oe  : out std_ulogic
      );
  end component;

end package swd;
