library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package fifo is

  component fifo_file_reader
    generic (
      width    : integer;
      filename : string
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      valid_o : out std_ulogic;
      ready_i : in  std_ulogic;
      data_o  : out std_ulogic_vector(width-1 downto 0);

      done_o : out std_ulogic
      );
  end component;

  component fifo_file_checker
    generic (
      width    : integer;
      filename : string
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i   : in std_ulogic;

      ready_o : out std_ulogic;
      valid_i : in  std_ulogic;
      data_i  : in  std_ulogic_vector(width-1 downto 0);

      done_o : out std_ulogic
      );
  end component;

  component fifo_counter_checker
    generic (
      width: integer
      );
    port (
      reset_n_i  : in  std_ulogic;
      clock_i     : in  std_ulogic;

      ready_o: out std_ulogic;
      valid_i: in std_ulogic;
      data_i: in std_ulogic_vector(width-1 downto 0)
      );
  end component;

  component fifo_counter_generator
    generic (
      width: integer
      );
    port (
      reset_n_i  : in  std_ulogic;
      clock_i     : in  std_ulogic;

      valid_o: out std_ulogic;
      ready_i: in std_ulogic;
      data_o: out std_ulogic_vector(width-1 downto 0)
      );
  end component;

  -- This emulates a delay on fifo between input and output.  Protocol
  -- wise, having the delay on p_in_ready is like having it on
  -- p_out_data and p_out_valid.
  component fifo_delay
    generic (
      width   : integer;
      latency : natural range 1 to 8
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i    : in std_ulogic;

      in_data_i  : in  std_ulogic_vector(width-1 downto 0);
      in_valid_i : in  std_ulogic;
      in_ready_o : out std_ulogic;

      out_data_o  : out std_ulogic_vector(width-1 downto 0);
      out_ready_i : in  std_ulogic;
      out_valid_o : out std_ulogic
      );
  end component;

  component fifo_sink
  generic (
    width: integer
    );
  port (
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    ready_o: out std_ulogic;
    valid_i: in std_ulogic;
    data_i: in std_ulogic_vector(width-1 downto 0)
    );
  end component;

end package fifo;
