library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.noc.all;

package noc is

  component noc_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_val   : out noc_cmd;
      p_out_ack   : in noc_rsp;

      p_done : out std_ulogic
      );
  end component;

  component noc_file_checker is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd;
      p_in_ack   : out noc_rsp;

      p_done     : out std_ulogic
      );
  end component;

end package noc;
