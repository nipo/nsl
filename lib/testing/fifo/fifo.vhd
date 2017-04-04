library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl;
use nsl.fifo.all;

package fifo is

  component fifo_counter_checker
    generic (
      width: integer
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_full_n: out std_ulogic;
      p_write: in std_ulogic;
      p_data: in std_ulogic_vector(width-1 downto 0)
      );
  end component;

  component fifo_counter_generator
    generic (
      width: integer
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_empty_n: out std_ulogic;
      p_read: in std_ulogic;
      p_data: out std_ulogic_vector(width-1 downto 0)
      );
  end component;

  component fifo_file_reader
    generic (
      width: integer;
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_empty_n: out std_ulogic;
      p_read: in std_ulogic;
      p_data: out std_ulogic_vector(width-1 downto 0);
      
      p_done: out std_ulogic
      );
  end component;

  component fifo_sink
  generic (
    width: integer
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_full_n: out std_ulogic;
    p_write: in std_ulogic;
    p_data: in std_ulogic_vector(width-1 downto 0)
    );
  end component;

  component fifo_file_checker
    generic (
      width: integer;
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_full_n: out std_ulogic;
      p_write: in std_ulogic;
      p_data: in std_ulogic_vector(width-1 downto 0);

      p_done     : out std_ulogic
      );
  end component;

  component fifo_framed_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp;

      p_done : out std_ulogic
      );
  end component;

  component fifo_framed_file_checker is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_done     : out std_ulogic
      );
  end component;

end package fifo;
