library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package noc is

  type noc_cmd is record
    data  :  std_ulogic_vector(7 downto 0);
    more  :  std_ulogic;
    val   :  std_ulogic;
  end record;

  type noc_rsp is record
    ack   :  std_ulogic;
  end record;

  type noc_cmd_array is array(natural range <>) of noc_cmd;
  type noc_rsp_array is array(natural range <>) of noc_rsp;

  type noc_routing_table is array(natural range 0 to 15) of natural;

  component noc_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      routing_table : noc_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out noc_rsp_array(in_port_count-1 downto 0);

      p_out_val   : out noc_cmd_array(out_port_count-1 downto 0);
      p_out_ack   : in noc_rsp_array(out_port_count-1 downto 0)
      );
  end component;

  component noc_router_inbound is
    generic(
      out_port_count : natural;
      routing_table : noc_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd;
      p_in_ack   : out noc_rsp;

      p_out_val  : out noc_cmd;
      p_out_ack  : in noc_rsp_array(out_port_count-1 downto 0);
      
      p_select : out std_ulogic_vector(out_port_count-1 downto 0)
      );
  end component;

  component noc_router_outbound is
    generic(
      in_port_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out noc_rsp;

      p_out_val  : out noc_cmd;
      p_out_ack  : in noc_rsp;

      p_select : in std_ulogic_vector(in_port_count-1 downto 0)
      );
  end component;

  component noc_fifo is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd;
      p_in_ack   : out noc_rsp;

      p_out_val   : out noc_cmd;
      p_out_ack   : in noc_rsp
      );
  end component;

  component noc_atomic_fifo is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in noc_cmd;
      p_in_ack   : out noc_rsp;

      p_out_val   : out noc_cmd;
      p_out_ack   : in noc_rsp
      );
  end component;

  component noc_async_fifo is
    generic(
      depth : natural
      );
    port(
      p_resetn    : in  std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_val    : in noc_cmd;
      p_in_ack    : out noc_rsp;

      p_out_clk   : in  std_ulogic;
      p_out_val   : out noc_cmd;
      p_out_ack   : in noc_rsp
      );
  end component;

end package noc;
