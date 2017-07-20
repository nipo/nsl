library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

package flit is

  subtype flit_data is std_ulogic_vector(7 downto 0);
  
  type flit_cmd is record
    data : flit_data;
    val  : std_ulogic;
  end record;

  type flit_ack is record
    ack  : std_ulogic;
  end record;

  type flit_cmd_array is array(natural range <>) of flit_cmd;
  type flit_ack_array is array(natural range <>) of flit_ack;

  component flit_fifo_sync
    generic(
      depth     : integer
      );
    port(
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_val  : in  flit_cmd;
      p_in_ack  : out flit_ack;

      p_out_val : out flit_cmd;
      p_out_ack : in  flit_ack
      );
  end component;

  component flit_from_framed
    generic(
      max_txn_length  : natural := 2048
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val  : in fifo_framed_cmd;
      p_in_ack  : out fifo_framed_rsp;

      p_out_val : out flit_cmd;
      p_out_ack : in  flit_ack
      );
  end component;

  component flit_to_framed
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_inval : out std_ulogic;
      
      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in  fifo_framed_rsp;

      p_in_val : in  flit_cmd;
      p_in_ack : out flit_ack
      );
  end component;

  component flit_fifo_async
    generic(
      depth     : integer
      );
    port(
      p_resetn  : in  std_ulogic;

      p_in_clk  : in  std_ulogic;
      p_in_val  : in  flit_cmd;
      p_in_ack  : out flit_ack;

      p_out_clk : in  std_ulogic;
      p_out_val : out flit_cmd;
      p_out_ack : in  flit_ack
      );
  end component;

end package flit;
