library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, nsl_i2c, work, unisim;

entity boundary is
  port (
    clk : in std_ulogic;

    sw : in std_ulogic_vector(0 to 1);
    led4_r, led4_g, led4_b, led5_r, led5_g, led5_b : out std_ulogic;
    led: out std_ulogic_vector(0 to 3);
    btn: in std_ulogic_vector(0 to 3);

    hdmi_tx_cec: inout std_logic;
    hdmi_tx_clk_n, hdmi_tx_clk_p : out std_ulogic;
    hdmi_tx_d_n, hdmi_tx_d_p: out std_ulogic_vector(0 to 2);
    hdmi_tx_hpdn: in std_ulogic;
    hdmi_tx_scl, hdmi_tx_sda: inout std_logic
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 125000000;

  signal hdmi_internal_term_d : std_ulogic_vector(0 to 2);
  signal hdmi_internal_term_clk : std_ulogic;

  signal hdmi_tx_cec_o: nsl_io.io.opendrain;
  signal hdmi_tx_hpd_s, hdmi_tx_cec_i: std_ulogic;
  
  type i2c_cs is
  record
    c : nsl_i2c.i2c.i2c_o;
    s : nsl_i2c.i2c.i2c_i;
  end record;
  
  signal hdmi_i2c_s: i2c_cs;
  signal roc_n_s, config_clock_unb_s, config_clock_s, clock_s, clock_reset_n_s : std_ulogic;
  
begin

  startup: unisim.vcomponents.startupe2
    port map (
      cfgmclk => config_clock_unb_s,
      eos => open,
      clk => '0',
      gsr => '0',
      gts => '0',
      keyclearb => '1',
      pack => '0',
      usrcclko => '0',
      usrcclkts => '1', -- Dont drive CCLK from config
      usrdoneo => '0',
      usrdonets => '1'
      );

  config_clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => config_clock_unb_s,
      clock_o => config_clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => config_clock_s,
      reset_n_o => roc_n_s
      );
  
  reset_gen: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => roc_n_s,
      data_o => clock_reset_n_s
      );

  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk,
      clock_o => clock_s
      );

  i2c_hdmi_driver: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => hdmi_tx_scl,
      bus_io.sda => hdmi_tx_sda,
      bus_i => hdmi_i2c_s.c,
      bus_o => hdmi_i2c_s.s
      );

  main: work.top.main
    generic map(
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => clock_reset_n_s,

      button_i => btn,
      switch_i => sw,
      led_o => led,
      led4_o.r => led4_r,
      led4_o.g => led4_g,
      led4_o.b => led4_b,
      led5_o.r => led5_r,
      led5_o.g => led5_g,
      led5_o.b => led5_b,
      
      hdmi_i2c_o => hdmi_i2c_s.c,
      hdmi_i2c_i => hdmi_i2c_s.s,
      hdmi_clock_o.p => hdmi_tx_clk_p,
      hdmi_clock_o.n => hdmi_tx_clk_n,
      hdmi_data_o(0).p => hdmi_tx_d_p(0),
      hdmi_data_o(0).n => hdmi_tx_d_n(0),
      hdmi_data_o(1).p => hdmi_tx_d_p(1),
      hdmi_data_o(1).n => hdmi_tx_d_n(1),
      hdmi_data_o(2).p => hdmi_tx_d_p(2),
      hdmi_data_o(2).n => hdmi_tx_d_n(2),
      hdmi_hpd_i => hdmi_tx_hpd_s,
      hdmi_cec_i => hdmi_tx_cec_i,
      hdmi_cec_o => hdmi_tx_cec_o
      );

  hdmi_tx_hpd_s <= not hdmi_tx_hpdn;

  cec: nsl_io.io.opendrain_io_driver
    port map(
      io_io => hdmi_tx_cec,
      v_o => hdmi_tx_cec_i,
      v_i => hdmi_tx_cec_o
      );
  
end architecture;
