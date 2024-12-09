library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.apb.all;
use nsl_data.text.all;

entity apb_dispatch is
  generic(
    config_c : config_t;
    routing_table_c : nsl_amba.address.address_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to routing_table_c'length-1);
    out_i : in slave_vector(0 to routing_table_c'length-1)
    );
end entity;

architecture beh of apb_dispatch is

  alias rt_c: nsl_amba.address.address_vector(0 to routing_table_c'length-1) is routing_table_c;
  signal sel_index_s: natural range 0 to routing_table_c'length-1;
  signal address_s: unsigned(config_c.address_width-1 downto 0);

begin

  address_s <= address(config_c, in_i, lsb => 0);
  sel_index_s <= nsl_amba.address.routing_table_lookup(
    config_c.address_width, rt_c, address_s);

  master_map: process(in_i, sel_index_s) is
  begin
    for i in out_o'range
    loop
      out_o(i) <= in_i;
      if sel_index_s = i then
        out_o(i).sel <= in_i.sel;
      else
        out_o(i).sel <= '0';
      end if;
    end loop;
  end process;

  in_o <= out_i(sel_index_s);
  
end architecture;
