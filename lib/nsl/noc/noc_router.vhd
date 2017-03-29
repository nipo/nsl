library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;

entity noc_router is
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
end entity;

architecture rtl of noc_router is

  signal s_cmd: noc_cmd_array(in_port_count-1 downto 0);
  signal s_rsp: noc_rsp_array(out_port_count-1 downto 0);

  subtype select_in_part_t is std_ulogic_vector(in_port_count-1 downto 0);
  type select_in_t is array(natural range 0 to out_port_count-1) of select_in_part_t;
  signal s_select_out : select_in_t;

  subtype select_out_part_t is std_ulogic_vector(out_port_count-1 downto 0);
  type select_out_t is array(natural range 0 to in_port_count-1) of select_out_part_t;
  signal s_select_in : select_out_t;

begin

  inbound: for in_port in 0 to in_port_count-1 generate
    inbound_inst: nsl.noc.noc_router_inbound
      generic map(
        out_port_count => out_port_count,
        routing_table => routing_table
        )
      port map(
        p_resetn => p_resetn,
        p_clk => p_clk,
        p_in_val => p_in_val(in_port),
        p_in_ack => p_in_ack(in_port),
        p_out_val => s_cmd(in_port),
        p_out_ack => s_rsp,
        p_select => s_select_in(in_port)
        );
  end generate;

  outbound: for out_port in 0 to out_port_count-1 generate
    outbound_inst: nsl.noc.noc_router_outbound
      generic map(
        in_port_count => in_port_count
        )
      port map(
        p_resetn => p_resetn,
        p_clk => p_clk,
        p_in_val => s_cmd,
        p_in_ack => s_rsp(out_port),
        p_out_val => p_out_val(out_port),
        p_out_ack => p_out_ack(out_port),
        p_select => s_select_out(out_port)
        );
  end generate;

  map_select: for in_port in 0 to in_port_count-1 generate
    map_select2: for out_port in 0 to out_port_count-1 generate
      s_select_out(out_port)(in_port) <= s_select_in(in_port)(out_port);
    end generate;
  end generate;
  
end architecture;
