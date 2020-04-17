library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_bnoc;

package testing is

  component sized_file_reader
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_val: out nsl_bnoc.sized.sized_req;
      p_out_ack: in nsl_bnoc.sized.sized_ack;
      
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

      p_in_val: in nsl_bnoc.sized.sized_req;
      p_in_ack: out nsl_bnoc.sized.sized_ack;

      p_done     : out std_ulogic
      );
  end component;

  component framed_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_val   : out nsl_bnoc.framed.framed_req;
      p_out_ack   : in nsl_bnoc.framed.framed_ack;

      p_done : out std_ulogic
      );
  end component;

  component framed_file_checker is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in nsl_bnoc.framed.framed_req;
      p_in_ack   : out nsl_bnoc.framed.framed_ack;

      p_done     : out std_ulogic
      );
  end component;

end package testing;
