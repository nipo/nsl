library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

-- Bnoc Routed convention.
--
-- Routed network is a specialization of a framed network where first byte in a
-- frame conveys routing information. Route byte is a couple of source and
-- destination indices (4-bit values, MSBs are source).
--
-- Above this routed network, usually, there is a framed network encapsulation
-- with tagged frames. Second byte in routed frames usually convey tad IDs.
-- This infrastructure is mostly suited for command/response-based blocks where
-- one command imples exactly one matching response frame.
package routed is

  subtype routed_req is nsl_bnoc.framed.framed_req;
  subtype routed_ack is nsl_bnoc.framed.framed_ack;
  subtype routed_bus is nsl_bnoc.framed.framed_bus;
  subtype routed_req_t is nsl_bnoc.framed.framed_req_t;
  subtype routed_ack_t is nsl_bnoc.framed.framed_ack_t;
  subtype routed_bus_t is nsl_bnoc.framed.framed_bus_t;

  constant routed_req_idle_c : routed_req_t := nsl_bnoc.framed.framed_req_idle_c;
  constant routed_ack_idle_c : routed_ack_t := nsl_bnoc.framed.framed_ack_idle_c;
  function routed_flit(data: nsl_bnoc.framed.framed_data_t;
                       last: boolean := false) return routed_req_t;
  
  type routed_req_array is array(natural range <>) of routed_req_t;
  type routed_ack_array is array(natural range <>) of routed_ack_t;
  type routed_bus_array is array(natural range <>) of routed_bus_t;
  
  subtype component_id is natural range 0 to 15;
  type routed_routing_table is array(component_id) of natural;

  -- Router interprets first flit of a frame and uses it to route the message
  -- to the destination port by dereferencing the routing table.
  -- Routing header is forwarded with no alteration.
  component routed_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      -- Routing table, as an array of output port index depending on routing
      -- destionation value.
      routing_table : routed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req_array(0 to in_port_count-1);
      p_in_ack   : out routed_ack_array(0 to in_port_count-1);

      p_out_val   : out routed_req_array(0 to out_port_count-1);
      p_out_ack   : in routed_ack_array(0 to out_port_count-1)
      );
  end component;

  -- Implementation detail of router
  component routed_router_inbound is
    generic(
      out_port_count : natural;
      routing_table : routed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req_t;
      p_in_ack   : out routed_ack_t;

      p_out_val  : out routed_req_t;
      p_out_ack  : in routed_ack_array(0 to out_port_count-1);

      p_request  : out std_ulogic_vector(0 to out_port_count-1);
      p_selected : in  std_ulogic_vector(0 to out_port_count-1)
      );
  end component;

  -- Implementation detail of router
  component routed_router_outbound is
    generic(
      in_port_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in routed_req_array(0 to in_port_count-1);
      p_in_ack   : out routed_ack_t;

      p_out_val  : out routed_req_t;
      p_out_ack  : in routed_ack_t;

      p_request  : in  std_ulogic_vector(0 to in_port_count-1);
      p_selected : out std_ulogic_vector(0 to in_port_count-1)
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
      routed_o  : out routed_req_t;
      routed_i  : in routed_ack_t
      );
  end component;

  -- This is the exit node for a one-way message. It strips routing
  -- information header.
  component routed_exit is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      routed_i  : in routed_req_t;
      routed_o  : out routed_ack_t;
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

      p_cmd_in_val   : in routed_req_t;
      p_cmd_in_ack   : out routed_ack_t;
      p_cmd_out_val   : out nsl_bnoc.framed.framed_req;
      p_cmd_out_ack   : in nsl_bnoc.framed.framed_ack;

      p_rsp_in_val   : in nsl_bnoc.framed.framed_req;
      p_rsp_in_ack   : out nsl_bnoc.framed.framed_ack;
      p_rsp_out_val   : out routed_req_t;
      p_rsp_out_ack   : in routed_ack_t
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

      routed_in_i   : in routed_req_t;
      routed_in_o   : out routed_ack_t;
      framed_out_o  : out nsl_bnoc.framed.framed_req;
      framed_out_i  : in nsl_bnoc.framed.framed_ack;

      framed_in_i   : in nsl_bnoc.framed.framed_req;
      framed_in_o   : out nsl_bnoc.framed.framed_ack;
      routed_out_o  : out routed_req_t;
      routed_out_i  : in routed_ack_t
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

      p_cmd_in_val   : in routed_req_t;
      p_cmd_in_ack   : out routed_ack_t;
      p_cmd_out_val   : out routed_req_t;
      p_cmd_out_ack   : in routed_ack_t;

      p_rsp_in_val   : in routed_req_t;
      p_rsp_in_ack   : out routed_ack_t;
      p_rsp_out_val   : out routed_req_t;
      p_rsp_out_ack   : in routed_ack_t
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
                       last: boolean := false) return routed_req_t
  is
  begin
    if last then
      return (valid => '1', data => data, last => '1');
    else
      return (valid => '1', data => data, last => '0');
    end if;
  end function;

end package body;
