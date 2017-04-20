library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.flit.all;

package flit is

  component flit_file_reader
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_val: out flit_cmd;
      p_out_ack: in flit_ack;
      
      p_done: out std_ulogic
      );
  end component;

  component flit_file_checker
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_val: in flit_cmd;
      p_in_ack: out flit_ack;

      p_done     : out std_ulogic
      );
  end component;

end package flit;
