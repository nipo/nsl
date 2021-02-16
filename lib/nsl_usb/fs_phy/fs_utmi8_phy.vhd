library ieee;
use ieee.std_logic_1164.all;

library nsl_usb;
use nsl_usb.utmi.all;
use nsl_usb.usb.all;
 
entity fs_utmi8_phy is
  generic (
    ref_clock_mhz_c : integer := 60
    );
  port (
    ref_clock_i      : in  std_ulogic;
    reset_n_i        : in  std_ulogic;
    tx_diff_mode_i    : in  std_ulogic := '1';

    bus_o : out nsl_usb.io.usb_io_c; 
    bus_i : in nsl_usb.io.usb_io_s;

    utmi_data_i : in utmi_data8_sie2phy;
    utmi_data_o : out utmi_data8_phy2sie;
    utmi_system_i : in utmi_system_sie2phy;
    utmi_system_o : out utmi_system_phy2sie
  );
end fs_utmi8_phy;
 
architecture rtl of fs_utmi8_phy is
 
  signal utmi_data : utmi_data8_phy2sie;
  signal fs_ce, rxen, rst : std_ulogic;
  signal bus_tx : nsl_usb.io.usb_io_c; 

begin

  utmi_data_o <= utmi_data after 2 ns;
  utmi_system_o.clock <= ref_clock_i;

  bus_o.dp_pullup_en <= '1' when utmi_system_i.term_select = UTMI_MODE_FS
                        and utmi_system_i.op_mode /= UTMI_OP_MODE_NON_DRIVING else '0';
  bus_o.dp <= bus_tx.dp;
  bus_o.dm <= bus_tx.dm;
  bus_o.oe <= bus_tx.oe when utmi_system_i.op_mode /= UTMI_OP_MODE_NON_DRIVING else '0';

  rxen <= not bus_tx.oe;

  i_tx_phy: nsl_usb.fs_phy.fs_utmi8_tx_phy
    port map (
      clock_i   => ref_clock_i,
      reset_n_i => reset_n_i,
      fs_ce     => fs_ce,
      diff_mode_i  => tx_diff_mode_i,
      
      bus_o => bus_tx,

      dataout_i  => utmi_data_i.data,
      txvalid_i  => utmi_data_i.tx_valid,
      txready_o  => utmi_data.tx_ready
      );
 
  i_rx_phy: nsl_usb.fs_phy.fs_utmi8_rx_phy
    generic map(
      ref_clock_mhz_c => ref_clock_mhz_c
      )
    port map (
      clock_i   => ref_clock_i,
      reset_n_i => reset_n_i,
      fs_ce_o   => fs_ce,

      bus_i => bus_i,

      datain_o   => utmi_data.data,
      rxvalid_o  => utmi_data.rx_valid,
      rxactive_o => utmi_data.rx_active,
      rxerror_o  => utmi_data.rx_error,
      rx_en_i    => rxen,
      linestate  => utmi_system_o.line_state
      );
 
end rtl;
