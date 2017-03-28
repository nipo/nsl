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

begin

  

end architecture;
