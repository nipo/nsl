library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, work;

entity mau_10baset_mau is
  generic (
    clock_i_hz_c : natural;
    collision_detect_c : boolean := true;
    slow_timer_div_c : natural := 1
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rx_i : in std_ulogic;
    tx_p_o : out std_ulogic;
    tx_n_o : out std_ulogic;
    tx_en_o : out std_ulogic;

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
    excessive_collision_o : out std_ulogic
    );
end entity;

architecture beh of mau_10baset_mau is

  signal carrier_s, link_pulse_s, frame_s, transmitting_s : std_ulogic;

begin

  tx: work.mau_10baset.mau_10baset_tx
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      collision_detect_c => collision_detect_c,
      slow_timer_div_c => slow_timer_div_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      flit_i => flit_i,
      ready_o => ready_o,

      carrier_i => carrier_s,

      transmitting_o => transmitting_s,

      collision_o => collision_o,
      late_collision_o => late_collision_o,
      excessive_collision_o => excessive_collision_o,

      tx_p_o => tx_p_o,
      tx_n_o => tx_n_o,
      tx_en_o => tx_en_o
      );

  rx: work.mau_10baset.mau_10baset_rx
    generic map(
      clock_i_hz_c => clock_i_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      rx_i => rx_i,

      flit_o => flit_o,
      valid_o => valid_o,

      carrier_o => carrier_s,
      link_pulse_o => link_pulse_s,
      frame_o => frame_s,
      polarity_inverted_o => polarity_inverted_o
      );

  monitor: work.mau_10baset.mau_10baset_link_monitor
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      slow_timer_div_c => slow_timer_div_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      link_pulse_i => link_pulse_s,
      frame_i => frame_s,

      link_up_o => link_up_o
      );

  crs_o <= carrier_s or transmitting_s;
  col_o <= carrier_s and transmitting_s;

end architecture;
