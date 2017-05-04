library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

package noc is

  subtype noc_id is natural range 0 to 15;
  function noc_flit_header(dst: noc_id;
                           src: noc_id)
    return flit_data;
  function noc_flit_header_dst(w: flit_data)
    return noc_id;
  function noc_flit_header_src(w: flit_data)
    return noc_id;
  
  type noc_routing_table is array(noc_id) of natural;

  component noc_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      routing_table : noc_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in flit_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out flit_ack_array(in_port_count-1 downto 0);

      p_out_val   : out flit_cmd_array(out_port_count-1 downto 0);
      p_out_ack   : in flit_ack_array(out_port_count-1 downto 0)
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

      p_in_val   : in flit_cmd;
      p_in_ack   : out flit_ack;

      p_out_val  : out flit_cmd;
      p_out_ack  : in flit_ack_array(out_port_count-1 downto 0);
      
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

      p_in_val   : in flit_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out flit_ack;

      p_out_val  : out flit_cmd;
      p_out_ack  : in flit_ack;

      p_select : in std_ulogic_vector(in_port_count-1 downto 0)
      );
  end component;

  component noc_from_framed
    generic(
      srcid       : noc_id;
      tgtid       : noc_id;
      data_depth  : natural := 256;
      txn_depth   : natural := 1
      );
    port(
      p_resetn   : in std_ulogic;
      p_clk      : in std_ulogic;

      p_tag      : in flit_data;

      p_in_val  : in fifo_framed_cmd;
      p_in_ack  : out fifo_framed_rsp;

      p_out_val : out flit_cmd;
      p_out_ack : in  flit_ack
      );
  end component;

  component noc_to_framed
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_tag      : out flit_data;

      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in  fifo_framed_rsp;

      p_in_val : in  flit_cmd;
      p_in_ack : out flit_ack
      );
  end component;

end package noc;

package body noc is

  function noc_flit_header(dst: noc_id;
                           src: noc_id)
    return flit_data is
  begin
    return flit_data(to_unsigned(src * 16 + dst, 8));
  end;

  function noc_flit_header_dst(w: flit_data)
    return noc_id is
  begin
    return to_integer(unsigned(w(3 downto 0)));
  end;
  
  function noc_flit_header_src(w: flit_data)
    return noc_id is
  begin
    return to_integer(unsigned(w(7 downto 4)));
  end;

end noc;
