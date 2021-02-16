library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_data;
use nsl_data.bytestream.byte;

package fs_phy is

  component fs_utmi8_phy is
    generic (
      ref_clock_mhz_c : integer := 60
      );
    port (
      ref_clock_i   : in std_ulogic;
      reset_n_i     : in std_ulogic;
      tx_diff_mode_i : in std_ulogic := '1';

      bus_o : out nsl_usb.io.usb_io_c; 
      bus_i : in nsl_usb.io.usb_io_s;

      utmi_data_i   : in  nsl_usb.utmi.utmi_data8_sie2phy;
      utmi_data_o   : out nsl_usb.utmi.utmi_data8_phy2sie;
      utmi_system_i : in  nsl_usb.utmi.utmi_system_sie2phy;
      utmi_system_o : out nsl_usb.utmi.utmi_system_phy2sie
      );
  end component;

  component fs_utmi8_tx_phy is
    port (
      clock_i          : in  std_ulogic;
      reset_n_i        : in  std_ulogic;
      fs_ce            : in  std_ulogic;
      diff_mode_i      : in  std_ulogic;

      bus_o : out nsl_usb.io.usb_io_c; 

      dataout_i        : in  byte;
      txvalid_i        : in  std_ulogic;
      txready_o        : out std_ulogic
      );
  end component;

  component fs_utmi8_rx_phy is
    generic (
      ref_clock_mhz_c : integer := 60
      );
    port (
      clock_i             : in  std_ulogic;
      reset_n_i       : in  std_ulogic;

      fs_ce_o         : out std_ulogic;
      bus_i : in nsl_usb.io.usb_io_s;

      datain_o        : out byte;
      rxvalid_o       : out std_ulogic;
      rxactive_o      : out std_ulogic;
      rxerror_o       : out std_ulogic;
      rx_en_i         : in  std_ulogic;
      linestate       : out nsl_usb.usb.usb_symbol_t
      );
  end component;

end package;
