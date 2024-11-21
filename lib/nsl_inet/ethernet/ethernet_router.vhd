library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ethernet.all;

entity ethernet_router is
  generic(
    destination_count_c : natural;
    -- Flit count to pass through at the start of a frame
    l1_header_length_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Address to lookup
    destination_address_o : out mac48_t;
    -- Request strobe, response MUST appear on destination_port_i on next cycle.
    destination_lookup_o : out std_ulogic;
    destination_port_i : in natural range 0 to destination_count_c - 1;

    in_i : in nsl_bnoc.committed.committed_req;
    in_o : out nsl_bnoc.committed.committed_ack;

    out_o : out nsl_bnoc.committed.committed_req_array(0 to destination_count_c-1);
    out_i : in nsl_bnoc.committed.committed_ack_array(0 to destination_count_c-1)
    );
end entity;

architecture beh of ethernet_router is

  signal s_in: nsl_bnoc.committed.committed_bus;
  signal s_daddr : byte_string(0 to 5);
  signal s_lookup: std_ulogic;

  signal s_out_o : nsl_bnoc.framed.framed_req_array(0 to destination_count_c-1);
  signal s_out_i : nsl_bnoc.framed.framed_ack_array(0 to destination_count_c-1);

begin

  receiver_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => s_daddr'length + 5,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_i,
      p_clk(0) => clock_i,

      p_in_val => in_i,
      p_in_ack => in_o,

      p_out_val => s_in.req,
      p_out_ack => s_in.ack
      );

  mapping: for i in 0 to destination_count_c-1
  generate
    s_out_i(i) <= out_i(i);
    out_o(i) <= s_out_o(i);
  end generate;
  
  router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => 1,
      out_count_c => destination_count_c,
      in_header_count_c => s_daddr'length,
      out_header_count_c => s_daddr'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i(0) => s_in.req,
      in_o(0) => s_in.ack,

      out_o => s_out_o,
      out_i => s_out_i,

      route_valid_o => s_lookup,
      route_header_o => s_daddr,
      route_source_o => open,

      route_ready_i => s_lookup,
      route_header_i => s_daddr,
      route_destination_i => destination_port_i
      );

  destination_address_o <= s_daddr;
  destination_lookup_o <= s_lookup;

end architecture;
