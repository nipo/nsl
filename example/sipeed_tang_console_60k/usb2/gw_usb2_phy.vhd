library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, work, nsl_clocking;
use work.softphy.all;
use nsl_usb.usb.all;
use nsl_usb.utmi.all;

entity gw_usb2_phy is
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    utmi_o: out utmi8_phy2sie;
    utmi_i: in utmi8_sie2phy;

    usb_dxp_io : inout std_logic;
    usb_dxn_io : inout std_logic;
    usb_rxdp_i : in std_logic;
    usb_rxdn_i : in std_logic;
    usb_pullup_en_o : out std_logic;
    usb_term_dp_io : inout std_logic;
    usb_term_dn_io : inout std_logic
    );
end entity;

architecture gw of gw_usb2_phy is

  signal fast_clock_s, pll_locked_s, termselect_s : std_ulogic;
  signal op_mode_s, xcvrselect_s, line_state_s : std_logic_vector(1 downto 0);
  
begin

  fast_clock: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => 60e6,
      output_hz_c => 960e6
      )
    port map(
      clock_i => clock_i,
      clock_o => fast_clock_s,
      reset_n_i => reset_n_i,
      locked_o => pll_locked_s
      );
  
  op_mode_s <= std_logic_vector(to_logic(utmi_i.system.op_mode));
  xcvrselect_s <= "0" & to_logic(utmi_i.system.xcvr_select);
  termselect_s <= to_logic(utmi_i.system.term_select);
  utmi_o.system.line_state <= to_usb_symbol(std_ulogic_vector(line_state_s));
  utmi_o.system.clock <= clock_i;
  -- utmi_i.system.suspend ?
  
  inst: work.softphy.usb2_0_softphy_top
    port map(
      clk_i => clock_i,
      fclk_i => fast_clock_s,
      pll_locked_i => pll_locked_s,

      rst_i => utmi_i.system.reset,

      usb_dxp_io => usb_dxp_io,
      usb_dxn_io => usb_dxn_io,
      usb_rxdp_i => usb_rxdp_i,
      usb_rxdn_i => usb_rxdn_i,
      usb_pullup_en_o => usb_pullup_en_o,
      usb_term_dp_io => usb_term_dp_io,
      usb_term_dn_io => usb_term_dn_io,
      
      utmi_op_mode_i => op_mode_s,
      utmi_xcvrselect_i => xcvrselect_s,
      utmi_termselect_i => termselect_s,
      utmi_linestate_o => line_state_s,

      utmi_data_out_i => std_logic_vector(utmi_i.data.data),
      utmi_txvalid_i => utmi_i.data.tx_valid,
      utmi_txready_o => utmi_o.data.tx_ready,

      std_ulogic_vector(utmi_data_in_o) => utmi_o.data.data,
      utmi_rxvalid_o => utmi_o.data.rx_valid,
      utmi_rxactive_o => utmi_o.data.rx_active,
      utmi_rxerror_o => utmi_o.data.rx_error
      );

end architecture;
