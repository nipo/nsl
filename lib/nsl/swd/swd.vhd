library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;

package swd is

  component swd_master is
    port(
      p_resetn    : in  std_ulogic;
      p_clk       : in  std_ulogic;

      p_in_val    : in noc_cmd;
      p_in_ack    : out noc_rsp;
      p_out_val   : out noc_cmd;
      p_out_ack   : in noc_rsp;

      p_swclk     : out std_ulogic;
      p_swdio_o   : out std_ulogic;
      p_swdio_i   : in std_ulogic;
      p_swdio_oe  : out std_ulogic
      );
  end component;

end package swd;
