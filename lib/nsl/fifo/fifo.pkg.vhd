library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fifo is
  
  component fifo_sync
    generic(
      data_width : integer;
      depth      : integer
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_ready    : in  std_ulogic;
      p_out_valid : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_valid  : in  std_ulogic;
      p_in_ready : out std_ulogic
      );
  end component;

  component fifo_async
    generic(
      data_width : integer;
      depth      : integer
      );
    port(
      p_resetn   : in  std_ulogic;

      p_out_clk     : in  std_ulogic;
      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_ready    : in  std_ulogic;
      p_out_valid : out std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_valid  : in  std_ulogic;
      p_in_ready : out std_ulogic
      );
  end component;

  -- This makes the readiness of output port stable. i.e. when
  -- deasserted, it is low for at least (latency) cycles. This way,
  -- input port can be used in a delay pipeline, with a
  -- fifo_delayed_writer at the other end.
  component fifo_input_stabilized
    generic (
      width   : integer;
      latency : natural range 1 to 8
      );
    port (
      p_resetn : in std_ulogic;
      p_clk    : in std_ulogic;

      p_in_data  : in  std_ulogic_vector(width-1 downto 0);
      p_in_valid : in  std_ulogic;
      p_in_ready : out std_ulogic;

      p_out_data  : out std_ulogic_vector(width-1 downto 0);
      p_out_ready : in  std_ulogic;
      p_out_valid : out std_ulogic
      );
  end component;

  component fifo_delayed_writer
    generic(
      width : integer;
      latency    : natural range 1 to 8
      );
    port(
      p_resetn            : in  std_ulogic;
      p_clk               : in  std_ulogic;

      p_in_data           : in  std_ulogic_vector(width-1 downto 0);
      p_in_valid          : in  std_ulogic;
      p_in_ready          : out std_ulogic;

      p_out_data          : out std_ulogic_vector(width-1 downto 0);
      p_out_ready_delayed : in  std_ulogic;
      p_out_valid         : out std_ulogic
      );
  end component;

  component fifo_sink
    generic (
      width: integer
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_ready : out std_ulogic;
      p_in_valid  : in std_ulogic;
      p_in_data   : in std_ulogic_vector(width-1 downto 0)
      );
  end component;

  component fifo_narrower
    generic(
      parts : integer;
      width_out : integer
      );
    port(
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_data    : out std_ulogic_vector(width_out-1 downto 0);
      p_out_ready    : in  std_ulogic;
      p_out_valid : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(parts*width_out-1 downto 0);
      p_in_valid  : in  std_ulogic;
      p_in_ready : out std_ulogic
      );
  end component;

end package fifo;