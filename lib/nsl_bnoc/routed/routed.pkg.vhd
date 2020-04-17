library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

package routed is

  subtype routed_req is nsl_bnoc.framed.framed_req;
  subtype routed_ack is nsl_bnoc.framed.framed_ack;

  type routed_bus is record
    req: routed_req;
    ack: routed_ack;
  end record;
  
  type routed_req_array is array(natural range <>) of routed_req;
  type routed_ack_array is array(natural range <>) of routed_ack;
  type routed_bus_array is array(natural range <>) of routed_bus;
  
  subtype component_id is natural range 0 to 15;
  type routed_routing_table is array(component_id) of natural;

  component routed_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      routing_table : routed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req_array(in_port_count-1 downto 0);
      p_in_ack   : out routed_ack_array(in_port_count-1 downto 0);

      p_out_val   : out routed_req_array(out_port_count-1 downto 0);
      p_out_ack   : in routed_ack_array(out_port_count-1 downto 0)
      );
  end component;

  component routed_router_inbound is
    generic(
      out_port_count : natural;
      routing_table : routed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req;
      p_in_ack   : out routed_ack;

      p_out_val  : out routed_req;
      p_out_ack  : in routed_ack_array(out_port_count-1 downto 0);

      p_request  : out std_ulogic_vector(out_port_count-1 downto 0);
      p_selected : in  std_ulogic_vector(out_port_count-1 downto 0)
      );
  end component;

  component routed_router_outbound is
    generic(
      in_port_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req_array(in_port_count-1 downto 0);
      p_in_ack   : out routed_ack;

      p_out_val  : out routed_req;
      p_out_ack  : in routed_ack;

      p_request  : in  std_ulogic_vector(in_port_count-1 downto 0);
      p_selected : out std_ulogic_vector(in_port_count-1 downto 0)
      );
  end component;

  component routed_endpoint
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_in_val   : in routed_req;
      p_cmd_in_ack   : out routed_ack;
      p_cmd_out_val   : out nsl_bnoc.framed.framed_req;
      p_cmd_out_ack   : in nsl_bnoc.framed.framed_ack;

      p_rsp_in_val   : in routed_req;
      p_rsp_in_ack   : out routed_ack;
      p_rsp_out_val   : out nsl_bnoc.framed.framed_req;
      p_rsp_out_ack   : in nsl_bnoc.framed.framed_ack
      );
  end component;

  component routed_gateway
    generic(
      source_id: component_id;
      target_id: component_id
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_in_val   : in routed_req;
      p_cmd_in_ack   : out routed_ack;
      p_cmd_out_val   : out routed_req;
      p_cmd_out_ack   : in routed_ack;

      p_rsp_in_val   : in routed_req;
      p_rsp_in_ack   : out routed_ack;
      p_rsp_out_val   : out routed_req;
      p_rsp_out_ack   : in routed_ack
      );
  end component;
  
  function routed_header(dst: component_id; src: component_id)
    return nsl_bnoc.framed.framed_data_t;
  function routed_header_dst(w: nsl_bnoc.framed.framed_data_t)
    return component_id;
  function routed_header_src(w: nsl_bnoc.framed.framed_data_t)
    return component_id;
end package routed;

package body routed is

  function routed_header(dst: component_id; src: component_id)
    return nsl_bnoc.framed.framed_data_t is
  begin
    return nsl_bnoc.framed.framed_data_t(to_unsigned(src * 16 + dst, 8));
  end;

  function routed_header_dst(w: nsl_bnoc.framed.framed_data_t)
    return component_id is
  begin
    return to_integer(unsigned(w(3 downto 0)));
  end;
  
  function routed_header_src(w: nsl_bnoc.framed.framed_data_t)
    return component_id is
  begin
    return to_integer(unsigned(w(7 downto 4)));
  end;

end package body routed;
