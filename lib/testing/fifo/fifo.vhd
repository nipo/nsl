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

      p_ready: out std_ulogic;
      p_valid: in std_ulogic;
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

      p_valid: out std_ulogic;
      p_ready: in std_ulogic;
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

      p_valid: out std_ulogic;
      p_ready: in std_ulogic;
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

    p_ready: out std_ulogic;
    p_valid: in std_ulogic;
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

      p_ready: out std_ulogic;
      p_valid: in std_ulogic;
      p_data: in std_ulogic_vector(width-1 downto 0);

      p_done     : out std_ulogic
      );
  end component;

end package fifo;
