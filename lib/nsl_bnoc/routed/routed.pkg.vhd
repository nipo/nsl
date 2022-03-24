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

  constant routed_req_idle_c : routed_req := nsl_bnoc.framed.framed_req_idle_c;
  constant routed_ack_idle_c : routed_ack := nsl_bnoc.framed.framed_ack_idle_c;
  function routed_flit(data: nsl_bnoc.framed.framed_data_t;
                       last: boolean := false) return routed_req;
  
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

  -- This is the entry node for a one-way message. It only inserts a routing
  -- information header.
  component routed_entry is
    generic(
      source_id_c : component_id
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      target_id_i : in component_id;

      framed_i   : in nsl_bnoc.framed.framed_req;
      framed_o   : out nsl_bnoc.framed.framed_ack;
      routed_o  : out routed_req;
      routed_i  : in routed_ack
      );
  end component;

  -- This is the exit node for a one-way message. It strips routing
  -- information header.
  component routed_exit is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      routed_i  : in routed_req;
      routed_o  : out routed_ack;
      framed_o : out nsl_bnoc.framed.framed_req;
      framed_i : in nsl_bnoc.framed.framed_ack
      );
  end component;

  -- This components strips routing information from routed network, pipes the
  -- frame in a framed network, and waits for exactly one response frame back,
  -- where it inserts back reverse routing information and tag.
  --
  -- Command/response frames must be balanced. Tag of response will match tag
  -- from command.
  component routed_endpoint
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_in_val   : in routed_req;
      p_cmd_in_ack   : out routed_ack;
      p_cmd_out_val   : out nsl_bnoc.framed.framed_req;
      p_cmd_out_ack   : in nsl_bnoc.framed.framed_ack;

      p_rsp_in_val   : in nsl_bnoc.framed.framed_req;
      p_rsp_in_ack   : out nsl_bnoc.framed.framed_ack;
      p_rsp_out_val   : out routed_req;
      p_rsp_out_ack   : in routed_ack
      );
  end component;

  -- This component strips incoming routing information for routed
  -- network initiated frames, and inserts routing information to framed
  -- network frames to push them in the routed network.
  --
  -- Target routing information is a pseudo-static parameter, but may
  -- be modified.  Source ID is a network parameter.
  --
  -- Tag added to incoming frames will be taken from last-seen routed message.
  -- This may not be strictly timely ordered because of fifos.
  component routed_framed_gateway is
    generic(
      source_id_c : component_id
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      target_id_i : in component_id;

      routed_in_i   : in routed_req;
      routed_in_o   : out routed_ack;
      framed_out_o  : out nsl_bnoc.framed.framed_req;
      framed_out_i  : in nsl_bnoc.framed.framed_ack;

      framed_in_i   : in nsl_bnoc.framed.framed_req;
      framed_in_o   : out nsl_bnoc.framed.framed_ack;
      routed_out_o  : out routed_req;
      routed_out_i  : in routed_ack
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

  function routed_flit(data: nsl_bnoc.framed.framed_data_t;
                       last: boolean := false) return routed_req
  is
  begin
    if last then
      return (valid => '1', data => data, last => '1');
    else
      return (valid => '1', data => data, last => '0');
    end if;
  end function;

end package body;
