library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_8023, nsl_mii, work;

entity pmod_ethernet_10baset_mau is
  generic(
    clock_i_hz_c : natural;
    rx_diff_term_c : boolean := true;
    collision_detect_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    pmod_io : inout nsl_digilent.pmod.pmod_double_t;

    flit_i : in nsl_mii.flit.mii_flit_t;
    ready_o : out std_ulogic;

    flit_o : out nsl_mii.flit.mii_flit_t;
    valid_o : out std_ulogic;

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

architecture beh of pmod_ethernet_10baset_mau is

  signal rx_s, tx_p_s, tx_n_s, tx_en_s : std_ulogic;

begin

  mdi: work.pmod_ethernet.pmod_ethernet_mdi
    generic map(
      rx_diff_term_c => rx_diff_term_c
      )
    port map(
      pmod_io => pmod_io,

      tx_p_i => tx_p_s,
      tx_n_i => tx_n_s,
      tx_en_i => tx_en_s,

      rx_o => rx_s
      );

  mau: nsl_8023.mau_10baset.mau_10baset_mau
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      collision_detect_c => collision_detect_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      rx_i => rx_s,
      tx_p_o => tx_p_s,
      tx_n_o => tx_n_s,
      tx_en_o => tx_en_s,

      flit_i => flit_i,
      ready_o => ready_o,

      flit_o => flit_o,
      valid_o => valid_o,

      link_up_o => link_up_o,
      polarity_inverted_o => polarity_inverted_o,
      crs_o => crs_o,
      col_o => col_o,
      collision_o => collision_o,
      late_collision_o => late_collision_o,
      excessive_collision_o => excessive_collision_o
      );

  probe_o.rx <= rx_s;
  probe_o.tx_p <= tx_p_s;
  probe_o.tx_en <= tx_en_s;

end architecture;
