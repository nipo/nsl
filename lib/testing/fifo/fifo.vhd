library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

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
      p_data: in std_ulogic_vector(width-1 downto 0)
      );
  end component;

end package fifo;
