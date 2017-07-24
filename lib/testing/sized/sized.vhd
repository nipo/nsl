library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.sized.all;

package sized is

  component sized_file_reader
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_val: out sized_req;
      p_out_ack: in sized_ack;
      
      p_done: out std_ulogic
      );
  end component;

  component sized_file_checker
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_val: in sized_req;
      p_in_ack: out sized_ack;

      p_done     : out std_ulogic
      );
  end component;

end package sized;
