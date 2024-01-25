library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_logic.logic;

entity wishbone_crossbar is
  generic(
    wb_config_c : wb_config_t;
    slave_count_c : natural;
    routing_mask_c : unsigned;
    routing_table_c : nsl_math.int_ext.integer_vector
    );
  port(
    clock_i : std_ulogic;
    reset_n_i : std_ulogic;

    master_i : in wb_req_t;
    master_o : out wb_ack_t;

    slave_o : out wb_req_vector(0 to slave_count_c-1);
    slave_i : in wb_ack_vector(0 to slave_count_c-1)
    );
end entity;

architecture beh of wishbone_crossbar is

  signal int_slave_o : wb_req_vector(0 to slave_count_c);
  signal int_slave_i : wb_ack_vector(0 to slave_count_c);

  subtype adr_t is unsigned(wb_config_c.adr_width-1 downto 0);
  constant x_routing_mask_c : adr_t := resize(routing_mask_c, adr_t'length);
  constant table_index_width_c : natural := nsl_logic.logic.popcnt(std_ulogic_vector(x_routing_mask_c));
  constant table_count_c : natural := 2 ** table_index_width_c;

  subtype table_index_u_t is unsigned(table_index_width_c-1 downto 0);
  subtype table_index_t is natural range 0 to table_count_c-1;
  subtype target_index_t is natural range 0 to slave_count_c;
  type target_index_vector is array (natural range 0 to table_count_c-1) of target_index_t;

  function routing_index_extract(adr, mask : adr_t) return table_index_u_t
  is
    variable index_u: table_index_u_t := (others => '0');
    variable target_bit: integer;
  begin
    target_bit := 0;

    for source_bit in 0 to mask'length-1
    loop
      if mask(source_bit) = '1' then
        index_u(target_bit) := adr(source_bit);
        target_bit := target_bit + 1;
      end if;
    end loop;

    return index_u;
  end function;

  function routing_table_gen return target_index_vector
  is
    alias x_routing_table_c : nsl_math.int_ext.integer_vector(0 to routing_table_c'length-1) is routing_table_c;
    variable ret: target_index_vector;
    variable route: target_index_t;
  begin
    for i in ret'range
    loop
      route := slave_count_c;

      if i < routing_table_c'length then
        if x_routing_table_c(i) < slave_count_c then
          route := x_routing_table_c(i);
        end if;
      end if;

      ret(i) := route;
    end loop;

    return ret;
  end function;

  constant routing_c : target_index_vector := routing_table_gen;

  signal target_s : target_index_t;

begin

  selection: process(master_i) is
    variable index_u: table_index_u_t;
    variable index_i: table_index_t;
  begin
    index_u := routing_index_extract(adr => wbc_address(wb_config_c, master_i),
                                     mask => x_routing_mask_c);
    index_i := to_integer(index_u);
    target_s <= routing_c(index_i);
  end process;

  req_route: process(target_s, master_i) is
  begin
    for i in int_slave_o'range
    loop
      int_slave_o(i) <= master_i;
      if target_s /= i then
        int_slave_o(i).stb <= '0';
      end if;
    end loop;
  end process;

  ack_route: process(int_slave_i) is
  begin
    master_o <= wbc_ack(wb_config_c);

    for i in int_slave_i'range
    loop
      if wb_config_c.bus_type = WB_CLASSIC_PIPELINED then
        if int_slave_i(i).stall = '1' then
          master_o.stall <= '1';
        end if;
      end if;

      if wb_config_c.error_supported then
        if int_slave_i(i).err = '1' then
          master_o.err <= '1';
        end if;
      end if;

      if wb_config_c.retry_supported then
        if int_slave_i(i).rty = '1' then
          master_o.rty <= '1';
        end if;
      end if;

      if int_slave_i(i).ack = '1' then
        master_o.ack <= '1';
        master_o.dat <= int_slave_i(i).dat;
        master_o.tgd <= int_slave_i(i).tgd;
      end if;
    end loop;
  end process;

  slave_o <= int_slave_o(0 to slave_count_c-1);
  int_slave_i(0 to slave_count_c-1) <= slave_i;

  error_gen: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if wbc_is_read(wb_config_c, int_slave_o(slave_count_c)) or wbc_is_write(wb_config_c, int_slave_o(slave_count_c)) then
        int_slave_i(slave_count_c) <= wbc_ack(wb_config_c, term => WB_TERM_ERROR);
      end if;
    end if;

    if reset_n_i = '0' then
      int_slave_i(slave_count_c) <= wbc_ack(wb_config_c);
    end if;
  end process;

end architecture;
