library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, nsl_i2c, work, nsl_digilent, nsl_sipeed;
use nsl_digilent.pmod.all;

entity boundary is
  port (
    clk_i : in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic;
    s_n_i: in std_ulogic_vector(1 to 2);

    hdmi_ck_p_o: out std_logic;
    hdmi_ck_n_o: out std_logic;
    hdmi_dp_o: out std_logic_vector(0 to 2);
    hdmi_dn_o: out std_logic_vector(0 to 2);
    hdmi_psv_io: inout std_logic;
    hdmi_hpd_io: inout std_logic;
    hdmi_ddc_sda_io: inout std_logic;
    hdmi_ddc_scl_io: inout std_logic;

    uart_rx_i: in std_logic;
    uart_tx_o: out std_logic
  );
end boundary;

architecture arch of boundary is

  constant clk_hz_c : natural := 50_000_000;
  signal clock_s, merged_reset_n_s, internal_reset_n_s, reset_n_s : std_ulogic;
  signal s_i: std_ulogic_vector(1 to 2);
  
begin

  s_i <= not s_n_i;
  
  clock_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_s
      );

  roc_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_s,
      reset_n_o => internal_reset_n_s
      );

  merged_reset_n_s <= internal_reset_n_s and not s_i(1);

  resync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_s,
      data_i => merged_reset_n_s,
      data_o => reset_n_s
      );
  
  main: work.top.main
    generic map(
      clock_i_hz_c => clk_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      led_o(0) => done_led_o,
      led_o(1) => ready_led_o,

      dvi_clock_o.p => hdmi_ck_p_o,
      dvi_clock_o.n => hdmi_ck_n_o,
      dvi_data_o(0).p => hdmi_dp_o(0),
      dvi_data_o(0).n => hdmi_dn_o(0),
      dvi_data_o(1).p => hdmi_dp_o(1),
      dvi_data_o(1).n => hdmi_dn_o(1),
      dvi_data_o(2).p => hdmi_dp_o(2),
      dvi_data_o(2).n => hdmi_dn_o(2),
      uart_i => uart_rx_i
      );

  uart_tx_o <= uart_rx_i;
  hdmi_hpd_io <= '0';
  hdmi_psv_io <= 'Z';

end architecture;
