library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity routed_router is
  generic(
    in_port_count : natural;
    out_port_count : natural;
    routing_table : nsl_bnoc.routed.routed_routing_table
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl_bnoc.routed.routed_req_array(0 to in_port_count-1);
    p_in_ack   : out nsl_bnoc.routed.routed_ack_array(0 to in_port_count-1);

    p_out_val   : out nsl_bnoc.routed.routed_req_array(0 to out_port_count-1);
    p_out_ack   : in nsl_bnoc.routed.routed_ack_array(0 to out_port_count-1)
    );
end entity;

architecture rtl of routed_router is

  signal s_req: nsl_bnoc.routed.routed_req_array(0 to in_port_count-1);
  signal s_ack: nsl_bnoc.routed.routed_ack_array(0 to out_port_count-1);

  subtype select_in_part_t is std_ulogic_vector(0 to in_port_count-1);
  type select_in_t is array(natural range 0 to out_port_count-1) of select_in_part_t;
  signal s_request_out, s_selected_in : select_in_t;

  subtype select_out_part_t is std_ulogic_vector(0 to out_port_count-1);
  type select_out_t is array(natural range 0 to in_port_count-1) of select_out_part_t;
  signal s_request_in, s_selected_out : select_out_t;

begin

  inbound: for in_port in 0 to in_port_count-1 generate
    inbound_inst: nsl_bnoc.routed.routed_router_inbound
      generic map(
        out_port_count => out_port_count,
        routing_table => routing_table
        )
      port map(
        p_resetn => p_resetn,
        p_clk => p_clk,
        p_in_val => p_in_val(in_port),
        p_in_ack => p_in_ack(in_port),
        p_out_val => s_req(in_port),
        p_out_ack => s_ack,
        p_request => s_request_in(in_port),
        p_selected => s_selected_out(in_port)
        );
  end generate;

  outbound: for out_port in 0 to out_port_count-1 generate
    outbound_inst: nsl_bnoc.routed.routed_router_outbound
      generic map(
        in_port_count => in_port_count
        )
      port map(
        p_resetn => p_resetn,
        p_clk => p_clk,
        p_in_val => s_req,
        p_in_ack => s_ack(out_port),
        p_out_val => p_out_val(out_port),
        p_out_ack => p_out_ack(out_port),
        p_request => s_request_out(out_port),
        p_selected => s_selected_in(out_port)
        );
  end generate;

  map_select: for in_port in 0 to in_port_count-1 generate
    map_select2: for out_port in 0 to out_port_count-1 generate
      s_request_out(out_port)(in_port) <= s_request_in(in_port)(out_port);
      s_selected_out(in_port)(out_port) <= s_selected_in(out_port)(in_port);
    end generate;
  end generate;
  
end architecture;
