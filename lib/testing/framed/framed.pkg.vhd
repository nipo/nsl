library ieee;
use ieee.std_logic_1164.all;

library nsl;
use nsl.framed.all;

package framed is

  component framed_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_val   : out nsl.framed.framed_req;
      p_out_ack   : in nsl.framed.framed_ack;

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

      p_in_val   : in nsl.framed.framed_req;
      p_in_ack   : out nsl.framed.framed_ack;

      p_done     : out std_ulogic
      );
  end component;

end package framed;
