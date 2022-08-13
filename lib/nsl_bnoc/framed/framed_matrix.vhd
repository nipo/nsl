library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity framed_matrix is
  generic(
    source_count_c : natural;
    destination_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    in_i   : in framed_req_array(0 to source_count_c - 1);
    in_o   : out framed_ack_array(0 to source_count_c - 1);

    source_i: in nsl_math.int_ext.integer_vector(0 to destination_count_c - 1);
    out_o   : out framed_req_array(0 to destination_count_c - 1);
    out_i   : in framed_ack_array(0 to destination_count_c - 1)
    );
end entity;

architecture beh of framed_matrix is

  subtype in_index_t is natural range 0 to source_count_c;
  type in_index_vector is array (natural range <>) of in_index_t;
  
  signal in_for_out_s : in_index_vector(0 to destination_count_c-1);
  signal in_s : framed_req_array(0 to source_count_c);

  subtype ack_filter_t is std_ulogic_vector(0 to destination_count_c-1);
  type ack_filter_vector is array (integer range <>) of ack_filter_t;

  signal ack_filter_s: ack_filter_vector(0 to source_count_c-1);
  
begin

  buf_in: for i in in_i'range
  generate
    in_s(i) <= in_i(i);
  end generate;
  in_s(source_count_c) <= framed_req_idle_c;

  map_route: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      in_for_out_s <= (others => source_count_c);
      ack_filter_s <= (others => (others => '0'));

      for o in source_i'range
      loop
        if source_i(o) >= 0 and source_i(o) < source_count_c then
          in_for_out_s(o) <= source_i(o);
          ack_filter_s(source_i(o))(o) <= '1';
        end if;
      end loop;
    end if;
  end process;

  map_out: for o in out_o'range
  generate
    out_o(o) <= in_s(in_for_out_s(o));
  end generate;

  map_in: process(ack_filter_s, out_i) is
    variable ready : std_ulogic;
  begin
    for i in in_o'range
    loop
      ready := '0';
      for o in out_i'range
      loop
        ready := ready or (ack_filter_s(i)(o) and out_i(o).ready);
      end loop;
      in_o(i).ready <= ready;
    end loop;
  end process;
  
end architecture;

  
