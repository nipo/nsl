library ieee;
use ieee.std_logic_1164.all;

library nsl_usb;

package softphy is

  component gw_usb2_phy is
    port(
      clock_i: in std_ulogic; -- 60MHz
      reset_n_i: in std_ulogic;

      utmi_o: out nsl_usb.utmi.utmi8_phy2sie;
      utmi_i: in nsl_usb.utmi.utmi8_sie2phy;

      usb_dxp_io : inout std_logic;
      usb_dxn_io : inout std_logic;
      usb_rxdp_i : in std_logic;
      usb_rxdn_i : in std_logic;
      usb_pullup_en_o : out std_logic;
      usb_term_dp_io : inout std_logic;
      usb_term_dn_io : inout std_logic
      );
  end component;
  
  component usb2_0_softphy_top is
    port(
      clk_i : in std_logic;
      rst_i : in std_logic;
      fclk_i : in std_logic;
      pll_locked_i : in std_logic;

      utmi_data_out_i : in std_logic_vector(7 downto 0);
      utmi_txvalid_i : in std_logic;
      utmi_op_mode_i : in std_logic_vector(1 downto 0);
      utmi_xcvrselect_i : in std_logic_vector(1 downto 0);
      utmi_termselect_i : in std_logic;
      utmi_data_in_o : out std_logic_vector(7 downto 0);
      utmi_txready_o : out std_logic;
      utmi_rxvalid_o : out std_logic;
      utmi_rxactive_o : out std_logic;
      utmi_rxerror_o : out std_logic;
      utmi_linestate_o : out std_logic_vector(1 downto 0);

      -- usb interface
      usb_dxp_io : inout std_logic;
      usb_dxn_io : inout std_logic;
      usb_rxdp_i : in std_logic;
      usb_rxdn_i : in std_logic;
      usb_pullup_en_o : out std_logic;
      usb_term_dp_io : inout std_logic;
      usb_term_dn_io : inout std_logic
      );
  end component;
end package;
