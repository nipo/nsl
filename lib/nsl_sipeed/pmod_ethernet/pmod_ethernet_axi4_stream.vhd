library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_mii, nsl_amba, work;

entity pmod_ethernet_axi4_stream is
  generic(
    clock_i_hz_c : natural;
    rx_diff_term_c : boolean := true;
    collision_detect_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    pmod_io : inout nsl_digilent.pmod.pmod_double_t;

    rx_o : out nsl_amba.axi4_stream.master_t;
    rx_i : in nsl_amba.axi4_stream.slave_t;

    tx_i : in nsl_amba.axi4_stream.master_t;
    tx_o : out nsl_amba.axi4_stream.slave_t;

    link_up_o : out std_ulogic;
    polarity_inverted_o : out std_ulogic;
    crs_o : out std_ulogic;
    col_o : out std_ulogic;
    collision_o : out std_ulogic;
    late_collision_o : out std_ulogic;
    excessive_collision_o : out std_ulogic;

    probe_o : out work.pmod_ethernet.pmod_ethernet_probe_t
    );
end entity;

architecture beh of pmod_ethernet_axi4_stream is

  signal rx_flit_s, tx_flit_s : nsl_mii.flit.mii_flit_t;
  signal rx_valid_s, tx_ready_s : std_ulogic;

begin

  mau: work.pmod_ethernet.pmod_ethernet_10baset_mau
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      rx_diff_term_c => rx_diff_term_c,
      collision_detect_c => collision_detect_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      pmod_io => pmod_io,

      flit_i => tx_flit_s,
      ready_o => tx_ready_s,

      flit_o => rx_flit_s,
      valid_o => rx_valid_s,

      link_up_o => link_up_o,
      polarity_inverted_o => polarity_inverted_o,
      crs_o => crs_o,
      col_o => col_o,
      collision_o => collision_o,
      late_collision_o => late_collision_o,
      excessive_collision_o => excessive_collision_o,

      probe_o => probe_o
      );

  to_stream: nsl_mii.flit.mii_flit_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => rx_flit_s,
      valid_i => rx_valid_s,

      out_o => rx_o,
      out_i => rx_i
      );

  from_stream: nsl_mii.flit.mii_flit_from_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => tx_i,
      in_o => tx_o,

      underrun_o => open,
      packet_o => open,

      flit_o => tx_flit_s,
      ready_i => tx_ready_s
      );

end architecture;
