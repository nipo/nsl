library ieee;
use ieee.std_logic_1164.all;

library nsl_logic;

-- Width adaptation between a protocol adapter (data_byte_count_c bytes
-- per word) and a transceiver fabric interface (interface_width_c bits
-- per word), for data and for the per-byte 8b10b sideband.
--
-- Sideband vectors carry one bit per byte, so they are
-- data_byte_count_c bits wide on the adapter side and
-- interface_width_c / 8 bits wide on the transceiver side.
entity lane_gearbox is
  generic(
    data_byte_count_c : natural;
    interface_width_c : natural
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Adapter side ---------------------------------------------------
    tx_data_i     : in std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
    tx_charisk_i  : in std_ulogic_vector(data_byte_count_c - 1 downto 0);
    tx_disp_frc_i : in std_ulogic_vector(data_byte_count_c - 1 downto 0);
    tx_disp_val_i : in std_ulogic_vector(data_byte_count_c - 1 downto 0);

    rx_data_o    : out std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
    rx_charisk_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);
    rx_disperr_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);
    rx_codeerr_o : out std_ulogic_vector(data_byte_count_c - 1 downto 0);

    -- Transceiver side -----------------------------------------------
    gt_tx_data_o     : out std_ulogic_vector(interface_width_c - 1 downto 0);
    gt_tx_charisk_o  : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
    gt_tx_disp_frc_o : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
    gt_tx_disp_val_o : out std_ulogic_vector(interface_width_c / 8 - 1 downto 0);

    gt_rx_data_i    : in std_ulogic_vector(interface_width_c - 1 downto 0);
    gt_rx_charisk_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
    gt_rx_disperr_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0);
    gt_rx_codeerr_i : in std_ulogic_vector(interface_width_c / 8 - 1 downto 0)
    );
end entity;

architecture beh of lane_gearbox is

  constant data_bit_count_c       : natural := data_byte_count_c * 8;
  constant interface_byte_count_c : natural := interface_width_c / 8;

begin

  gearbox_datafromrx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => interface_width_c,
      output_width_c  => data_bit_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => gt_rx_data_i,
      out_o     => rx_data_o
      );

  gearbox_controlfromrx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => interface_byte_count_c,
      output_width_c  => data_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => gt_rx_charisk_i,
      out_o     => rx_charisk_o
      );

  gearbox_disperrfromrx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => interface_byte_count_c,
      output_width_c  => data_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => gt_rx_disperr_i,
      out_o     => rx_disperr_o
      );

  gearbox_codeerrfromrx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => interface_byte_count_c,
      output_width_c  => data_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => gt_rx_codeerr_i,
      out_o     => rx_codeerr_o
      );

  gearbox_datatotx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => data_bit_count_c,
      output_width_c  => interface_width_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => tx_data_i,
      out_o     => gt_tx_data_o
      );

  gearbox_controltotx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => data_byte_count_c,
      output_width_c  => interface_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => tx_charisk_i,
      out_o     => gt_tx_charisk_o
      );

  gearbox_dispfrctotx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => data_byte_count_c,
      output_width_c  => interface_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => tx_disp_frc_i,
      out_o     => gt_tx_disp_frc_o
      );

  gearbox_dispvaltotx : nsl_logic.gearbox.gearbox_c2c
    generic map (
      input_width_c   => data_byte_count_c,
      output_width_c  => interface_byte_count_c,
      left_to_right_c => false
      )
    port map (
      clock_i   => clock_i,
      reset_n_i => reset_n_i,
      in_i      => tx_disp_val_i,
      out_o     => gt_tx_disp_val_o
      );

end architecture;
