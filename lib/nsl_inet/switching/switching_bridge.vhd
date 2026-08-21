library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_inet;
use nsl_inet.ethernet.all;
use nsl_inet.switching.all;

entity switching_bridge is
  generic(
    config_c: config_t;
    static_macs_c: mac48_vector := no_static_macs_c;
    static_ports_c: port_index_vector := no_static_ports_c
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    flood_mask_i: in port_mask_t := (others => '1');

    in_i: in nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
    in_o: out nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1);

    out_o: out nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
    out_i: in nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1)
    );
end entity;

-- Structural assembly: one ingress per port, one shared MAC table, one
-- fabric. Vector index is the port index throughout, so the ingress of
-- port i owns index i of the lookup, learn and forwarding vectors.
architecture beh of switching_bridge is

  signal query_s: lookup_query_vector(0 to config_c.port_count-1);
  signal result_s: lookup_result_vector(0 to config_c.port_count-1);
  signal learn_s: learn_vector(0 to config_c.port_count-1);

  signal frame_m_s: nsl_amba.axi4_stream.master_vector(0 to config_c.port_count-1);
  signal frame_s_s: nsl_amba.axi4_stream.slave_vector(0 to config_c.port_count-1);
  signal forward_req_s: forward_req_vector(0 to config_c.port_count-1);
  signal forward_ack_s: forward_ack_vector(0 to config_c.port_count-1);

begin

  ports: for i in 0 to config_c.port_count-1 generate
    ingress: nsl_inet.switching.switching_ingress
      generic map(
        config_c => config_c,
        port_index_c => i
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        flood_mask_i => flood_mask_i,

        in_i => in_i(i),
        in_o => in_o(i),

        lookup_query_o => query_s(i),
        lookup_result_i => result_s(i),
        learn_o => learn_s(i),

        frame_o => frame_m_s(i),
        frame_i => frame_s_s(i),
        forward_o => forward_req_s(i),
        forward_i => forward_ack_s(i)
        );
  end generate;

  table: nsl_inet.switching.switching_mac_table
    generic map(
      config_c => config_c,
      static_macs_c => static_macs_c,
      static_ports_c => static_ports_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      query_i => query_s,
      result_o => result_s,

      learn_i => learn_s
      );

  fabric: nsl_inet.switching.switching_fabric
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      frame_i => frame_m_s,
      frame_o => frame_s_s,
      forward_i => forward_req_s,
      forward_o => forward_ack_s,

      out_o => out_o,
      out_i => out_i
      );

end architecture;
