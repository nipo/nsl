library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use work.vlan.all;
use work.stream_vlan.all;

entity stream_vlan_path_router is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    vlan_id_c : vlan_id_vector;
    native_vlan_id_c : vlan_id_t := 0;
    l1_has_fcs_c : boolean := true;
    routed_has_fcs_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rx_vlan_i : in master_t;
    rx_vlan_o : out slave_t;

    tx_vlan_o : out master_t;
    tx_vlan_i : in slave_t;

    rx_routed_o : out master_vector(0 to vlan_id_c'length-1);
    rx_routed_i : in slave_vector(0 to vlan_id_c'length-1);

    tx_routed_i : in master_vector(0 to vlan_id_c'length-1);
    tx_routed_o : out slave_vector(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of stream_vlan_path_router is

  constant pipe_count_c : natural := vlan_id_c'length;

  signal rx_s, tx_s : bus_t;
  signal rx_pipe_m_s, tx_pipe_m_s : master_vector(0 to pipe_count_c-1);
  signal rx_pipe_s_s, tx_pipe_s_s : slave_vector(0 to pipe_count_c-1);

begin

  rx_mac: work.stream_mac.stream_mac_receiver
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      l1_has_fcs_c => l1_has_fcs_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => rx_vlan_i,
      in_o => rx_vlan_o,

      out_o => rx_s.m,
      out_i => rx_s.s
      );

  demux: work.stream_vlan.stream_vlan_demux
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      vlan_id_c => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => rx_s.m,
      in_o => rx_s.s,

      out_o => rx_pipe_m_s,
      out_i => rx_pipe_s_s
      );

  mux: work.stream_vlan.stream_vlan_mux
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      vlan_id_c => vlan_id_c,
      native_vlan_id_c => native_vlan_id_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => tx_pipe_m_s,
      in_o => tx_pipe_s_s,

      out_o => tx_s.m,
      out_i => tx_s.s
      );

  tx_mac: work.stream_mac.stream_mac_transmitter
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      l1_has_fcs_c => l1_has_fcs_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => tx_s.m,
      in_o => tx_s.s,

      out_o => tx_vlan_o,
      out_i => tx_vlan_i
      );

  pipes: for i in 0 to pipe_count_c-1
  generate
    mac_boundary: if not routed_has_fcs_c
    generate
      rx_routed_o(i) <= rx_pipe_m_s(i);
      rx_pipe_s_s(i) <= rx_routed_i(i);

      tx_pipe_m_s(i) <= tx_routed_i(i);
      tx_routed_o(i) <= tx_pipe_s_s(i);
    end generate;

    layer1: if routed_has_fcs_c
    generate
      rx_fcs: work.stream_mac.stream_mac_transmitter
        generic map(
          config_c => config_c,
          header_length_c => header_length_c,
          l1_has_fcs_c => true
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => rx_pipe_m_s(i),
          in_o => rx_pipe_s_s(i),

          out_o => rx_routed_o(i),
          out_i => rx_routed_i(i)
          );

      tx_fcs: work.stream_mac.stream_mac_receiver
        generic map(
          config_c => config_c,
          header_length_c => header_length_c,
          l1_has_fcs_c => true
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i => tx_routed_i(i),
          in_o => tx_routed_o(i),

          out_o => tx_pipe_m_s(i),
          out_i => tx_pipe_s_s(i)
          );
    end generate;
  end generate;

end architecture;
