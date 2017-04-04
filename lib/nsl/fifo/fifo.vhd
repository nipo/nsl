library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;

package fifo is

  type fifo_framed_cmd is record
    data : std_ulogic_vector(7 downto 0);
    more : std_ulogic;
    val  : std_ulogic;
  end record;

  type fifo_framed_rsp is record
    ack  : std_ulogic;
  end record;

  type fifo_framed_cmd_array is array(natural range <>) of fifo_framed_cmd;
  type fifo_framed_rsp_array is array(natural range <>) of fifo_framed_rsp;

  component fifo_sync
    generic(
      data_width : integer;
      depth      : integer
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
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
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
      );
  end component;

  component fifo_sink
    generic (
      width: integer
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_full_n : out std_ulogic;
      p_in_write  : in std_ulogic;
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
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(parts*width_out-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
      );
  end component;

  component fifo_framed is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_atomic is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_async is
    generic(
      depth : natural
      );
    port(
      p_resetn    : in  std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_val    : in fifo_framed_cmd;
      p_in_ack    : out fifo_framed_rsp;

      p_out_clk   : in  std_ulogic;
      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

end package fifo;
