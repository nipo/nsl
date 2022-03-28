library ieee;
use ieee.std_logic_1164.all;

library nsl_mii, nsl_clocking, nsl_smi, work, nsl_hwdep, nsl_io, nsl_bnoc;

entity fpga_io is
  port(
    clk100mhz: in std_ulogic;

    uart_rxd_out: out std_ulogic;
    uart_txd_in: in std_ulogic;

    eth_col : in std_ulogic;
    eth_crs : in std_ulogic;
    eth_mdc : out std_ulogic;
    eth_mdio : inout std_logic;
    eth_ref_clk : out std_ulogic;
    eth_rstn : inout std_logic;
    eth_rx_clk : in std_ulogic;
    eth_rx_dv : in std_ulogic;
    eth_rxd : in std_ulogic_vector(3 downto 0);
    eth_rxerr : in std_ulogic;
    eth_tx_clk : in std_ulogic;
    eth_tx_en : out std_ulogic;
    eth_txd : out std_ulogic_vector(3 downto 0);

    btn: in std_ulogic_vector(0 to 3);
    led: out std_ulogic_vector(0 to 3)
    );
end entity;

architecture beh of fpga_io is

  signal clock_25_s, clock_100_s, reset_n_25_s, reset_n_s, ext_reset_n_s: std_ulogic;
  signal eth_smi_s : nsl_smi.smi.smi_master_i;
  signal eth_smi_c : nsl_smi.smi.smi_master_o;
  type comm_trx is
  record
    tx, rx: nsl_bnoc.committed.committed_bus;
  end record;
  signal l1_s: comm_trx;
  signal led_s: std_ulogic_vector(0 to 3);
  signal eth_tx_er: std_ulogic;

begin

  buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk100mhz,
      clock_o => clock_100_s
      );
      
  
  clk25: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => 100e6,
      output_hz_c => 25e6,
      hw_variant_c => "series67(type=pll)"
      )
    port map(
      clock_i => clock_100_s,
      clock_o => clock_25_s,
      reset_n_i => reset_n_s,
      locked_o => reset_n_25_s
      );

  phy_ref_clock: nsl_io.clock.clock_output_se_to_se
    port map(
      clock_i => clock_25_s,
      port_o => eth_ref_clk
      );

  ext_reset_n_s <= not btn(0);
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_100_s,
      data_i => ext_reset_n_s,
      data_o => reset_n_s
      );

  eth_rstn <= '0' when reset_n_25_s = '0' else 'Z';

  main_inst: work.func.func_main
    generic map(
      clock_hz_c => 100e6
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      net_smi_o => eth_smi_c,
      net_smi_i => eth_smi_s,
      net_to_l1_o => l1_s.tx.req,
      net_to_l1_i => l1_s.tx.ack,
      net_from_l1_i => l1_s.rx.req,
      net_from_l1_o => l1_s.rx.ack,

      button_i => btn,
      led_o => led_s,

      uart_o => uart_rxd_out,
      uart_i => uart_txd_in
      );

  led_driver: for i in led'range
  generate
    led(i) <= '1' when led_s(i) = '1' else 'Z';
  end generate;

  mii: nsl_mii.mii.mii_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_100_s,

      mii_i.rx.clk => eth_rx_clk,
      mii_i.rx.d => eth_rxd,
      mii_i.rx.dv => eth_rx_dv,
      mii_i.rx.er => eth_rxerr,
      mii_i.tx.clk => eth_tx_clk,
      mii_i.status.crs => eth_crs,
      mii_i.status.col => eth_col,
      mii_o.tx.d => eth_txd,
      mii_o.tx.en => eth_tx_en,
      mii_o.tx.er => eth_tx_er,

      rx_o => l1_s.rx.req,
      rx_i => l1_s.rx.ack,

      tx_i => l1_s.tx.req,
      tx_o => l1_s.tx.ack
      );      

  mdio_driver: nsl_smi.smi.smi_master_line_driver
    port map(
      mdc_o => eth_mdc,
      mdio_io => eth_mdio,
      master_o => eth_smi_s,
      master_i => eth_smi_c
      );

end architecture;
